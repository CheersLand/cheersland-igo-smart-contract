// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./../owner/Auth.sol";
import "./../interface/IMiningLpPool.sol";

contract FundraisingIdoPool is Auth {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;


    address private _adminAddress;

    address public poolAddress;

    address public lpAddress;

    uint256 public threshold;

    uint256 public lpQuantitySold;

    uint256 public totalIssuance;

    uint256 public startTime;

    uint256 public endTime;

    uint256 public claimTime;

    address public fundRaisingAddress;

    uint256 public totalFundRaising;

    uint256 public whiteListQuota;

    bool public claimLock;

    bool public ownerClaimLock;

    mapping(uint8 => uint256) public exchangeRate;

    mapping(address => uint256) public upperLimit;

    mapping(address => uint8) public whiteList;

    mapping(uint8 => address[]) public whiteListArr;

    mapping(address => uint256) public whiteListIndex;

    address[] public numberParticipants;

    uint256 public totalAmountInvested;

    uint256 public availableLimit;

    struct IdoInfo {
        uint256 index;
        uint256 investment;
    }

    mapping(address => IdoInfo) public userIdoInfo;

    mapping(address => bool) public userIsClaim;


    event SetWhiteList(address indexed user, uint8 rank);

    event ParticipateExchange(address indexed user, uint256 amount);

    event Claim(address indexed user, uint256 obtain, uint256 investment, uint256 exchange, uint256 retrievable);

    event OwnerClaim(address indexed user, uint256 amount, uint256 lpBalance);


    constructor(
        address _admin,
        address _lpAddress,
        uint256 _totalIssuance,
        uint256 _price,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _claimTime,
        address _fundRaisingAddress,
        uint256 _totalFundRaising,
        uint256 _whiteListQuota,
        uint256 _threshold
    ) public {
        require(_admin != address(0), "Admin address cannot be 0!");
        _adminAddress = _admin;
        require(_lpAddress != address(0), "LP address cannot be 0!");
        lpAddress = _lpAddress;
        totalIssuance = _totalIssuance;
        lpQuantitySold = _price.mul(_totalFundRaising).mul(1e18);
        startTime = _startTime;
        endTime = _endTime;
        claimTime = _claimTime;
        require(_fundRaisingAddress != address(0), "Fund raising address cannot be 0!");
        fundRaisingAddress = _fundRaisingAddress;
        totalFundRaising = _totalFundRaising.mul(1e18);
        whiteListQuota = _whiteListQuota.mul(1e18);
        exchangeRate[1] = 1;
        exchangeRate[2] = _price;
        threshold = _threshold.mul(1e18);
    }

    modifier inspectLock() {
        require(!claimLock, "Lock occupied!");
        claimLock = true;
        _;
        claimLock = false;
    }

    modifier inspectOwnerLock() {
        require(!ownerClaimLock, "Lock occupied!");
        ownerClaimLock = true;
        _;
        ownerClaimLock = false;
    }

    function setPoolAddress(address _pool) public onlyOperator {
        require(_pool != address(0), "Pool address cannot be 0!");
        poolAddress = _pool;
    }

    function setAdminAddress(address _admin) public onlyOperator {
        require(_admin != address(0), "Admin address cannot be 0!");
        _adminAddress = _admin;
    }

    function setWhiteListQuota(uint256 _quota) public onlyOperator {
        whiteListQuota = _quota;
    }

    function setExchangeRate(uint256 _material, uint256 _exchange) public onlyOperator {
        exchangeRate[1] = _material;
        exchangeRate[2] = _exchange;
    }

    function setUpperLimit(address _account, uint256 _quota) public onlyOperator {
        upperLimit[_account] = _quota;
    }

    function setEndTime(uint256 _endTime) public onlyOperator {
        endTime = _endTime;
    }

    function setClaimTime(uint256 _claimTime) public onlyOperator {
        claimTime = _claimTime;
    }

    function setThreshold(uint256 _threshold) public onlyOperator {
        threshold = _threshold;
    }

    function addSuperWhiteList(address[] calldata _accounts, uint256[] calldata _quotas) external onlyOperator {
        require(_accounts.length > 0 && _quotas.length > 0, "The number of whitelists added cannot be 0!");
        require(_accounts.length == _quotas.length, "The number of white lists added and the number of quotas are not equal!");

        for(uint256 i = 0; i < _accounts.length; i++) {
            require(_accounts[i] != address(0), "Account address cannot be 0!");
            if (whiteList[_accounts[i]] != 2) {
                setWhiteList(_accounts[i], 2);
                setUpperLimit(_accounts[i], _quotas[i].mul(1e18));
            }
        }
    }

    function _setWhiteList(address _account, uint8 _rank) internal {
        require(_account != address(0), "Account address cannot be 0!");
        require(_rank < 4, "Invalid whitelist rank setting!");

        uint8 rank = whiteList[_account];

        if (rank != _rank) {

            if (rank != 0) {
                uint256 length = whiteListArr[rank].length;
                uint256 index = whiteListIndex[_account];

                if (index != length.sub(1)) {
                    whiteListArr[rank][index] = whiteListArr[rank][length.sub(1)];
                    whiteListIndex[whiteListArr[rank][index]] = index;
                }
                whiteListArr[rank].pop();
            }

            whiteList[_account] = _rank;

            if (_rank == 1 && rank == 0) {
                upperLimit[_account] = whiteListQuota;
            }

            if (_rank != 0) {
                whiteListIndex[_account] = whiteListArr[_rank].length;
                whiteListArr[_rank].push(_account);
            } else {
                whiteListIndex[_account] = 0;
            }
        }
    }

    function setWhiteList(address _account, uint8 _rank) public onlyOperator {
        _setWhiteList(_account, _rank);
        emit SetWhiteList(_account, _rank);
    }

    function participateExchange(uint256 _amount) public {
        require(_amount > 0, "Exchange amount cannot be zero!");
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Not in IDO time range at this time!");

        uint256 mortgageNum = IMiningLpPool(poolAddress).getMortgageNum(msg.sender);
        uint8 rank = whiteList[msg.sender];

        if (mortgageNum >= threshold && rank == 0) {
            _setWhiteList(msg.sender, 1);
        } else {
            require(rank == 1 || rank == 2, "You don't have permission to participate!");
        }

        uint256 quota = upperLimit[msg.sender];
        uint256 investment = userIdoInfo[msg.sender].investment;
        require(_amount <= quota && (investment.add(_amount) <= quota), "Input limit exceeded!");

        if (investment == 0) {
            userIdoInfo[msg.sender].index = numberParticipants.length;
            numberParticipants.push(msg.sender);
        }

        totalAmountInvested = totalAmountInvested.add(_amount);
        userIdoInfo[msg.sender].investment = userIdoInfo[msg.sender].investment.add(_amount);

        IERC20(fundRaisingAddress).safeTransferFrom(msg.sender, address(this), _amount);

        emit ParticipateExchange(msg.sender, _amount);
    }

    function claim() public inspectLock {
        require(block.timestamp >= claimTime, "Claim time not reached!");
        require(!userIsClaim[msg.sender], "You have received the reward!");

        uint256 proportion;
        uint256 obtain;
        uint256 exchange;
        uint256 retrievable;
        uint256 balance;
        uint256 quota;
        uint256 availableAuota;

        (proportion,
        obtain,
        exchange,
        retrievable,
        balance,
        quota,
        availableAuota
        ) = getExchangeInfo(msg.sender);

        if (obtain > 0) {
            IERC20(lpAddress).safeTransfer(msg.sender, obtain);
        }
        if (retrievable > 0) {
            IERC20(fundRaisingAddress).safeTransfer(msg.sender, retrievable);
        }

        userIsClaim[msg.sender] = true;

        emit Claim(msg.sender, obtain, userIdoInfo[msg.sender].investment, exchange, retrievable);
    }

    function ownerClaim() public onlyOperator inspectOwnerLock {
        require(block.timestamp >= claimTime, "Claim time not reached!");
        require(msg.sender == _adminAddress, "You do not have administrator privileges!");
        require(!userIsClaim[msg.sender], "You have received the reward!");

        uint256 lpBalance = 0;

        if (totalAmountInvested < totalFundRaising) {
            availableLimit = totalAmountInvested;

            lpBalance = lpQuantitySold.sub(totalAmountInvested.mul(exchangeRate[2]));
            if (lpBalance > 0) {
                IERC20(lpAddress).safeTransfer(msg.sender, lpBalance);
            }
        } else {
            availableLimit = totalFundRaising;
        }

        if (availableLimit > 0) {
            IERC20(fundRaisingAddress).safeTransfer(msg.sender, availableLimit);
        }

        userIsClaim[msg.sender] = true;

        emit OwnerClaim(msg.sender, availableLimit, lpBalance);
    }

    function getPoolMortgage(address _account) public view returns (uint256) {
        return IMiningLpPool(poolAddress).getMortgageNum(_account);
    }

    function getThreshold() public view returns (uint256) {
        return threshold;
    }

    function isThreshold(address _account) public view returns (bool) {
        return IMiningLpPool(poolAddress).getMortgageNum(_account) >= threshold;
    }

    function isStart() public view returns (bool) {
        return block.timestamp >= startTime;
    }

    function isEnd() public view returns (bool) {
        return block.timestamp > endTime;
    }

    function isClaim() public view returns (bool) {
        return block.timestamp >= claimTime;
    }

    function isClaimByUser(address _account) public view returns (bool) {
        return userIsClaim[_account];
    }

    function isMortgage(address _account) public view returns (bool) {
        return userIdoInfo[_account].investment > 0;
    }

    function isAdmin() public view returns (bool) {
        return msg.sender == _adminAddress;
    }

    function isWhiteList(address _account) public view returns (uint8) {
        return whiteList[_account];
    }

    function getWhiteList(uint8 _rank) public view returns (address[] memory) {
        return whiteListArr[_rank];
    }

    function getNumberParticipants() public view returns (uint256) {
        return numberParticipants.length;
    }

    function getExchangeInfo(address _account) public view returns (
        uint256 proportion,
        uint256 obtain,
        uint256 exchange,
        uint256 retrievable,
        uint256 balance,
        uint256 quota,
        uint256 availableAuota
    ) {
        if (totalAmountInvested < totalFundRaising) {
            proportion = userIdoInfo[_account].investment.mul(1e18).div(totalFundRaising);
            obtain = userIdoInfo[_account].investment.mul(exchangeRate[2]).div(exchangeRate[1]);
        } else {
            proportion = userIdoInfo[_account].investment.mul(1e18).div(totalAmountInvested);
            obtain = userIdoInfo[_account].investment.mul(totalFundRaising).mul(exchangeRate[2]);
            obtain = obtain.div(exchangeRate[1]).div(totalAmountInvested);
        }
        proportion = proportion.mul(100).div(1e18);
        exchange = obtain.mul(exchangeRate[1]).div(exchangeRate[2]);
        retrievable = userIdoInfo[_account].investment.sub(exchange);

        balance = IERC20(fundRaisingAddress).balanceOf(_account);

        uint8 rank = whiteList[_account];
        if (rank == 1 || rank == 2 || rank == 3) {
            quota = upperLimit[_account];
            availableAuota = quota.sub(userIdoInfo[_account].investment);
        }

        uint256 mortgageNum = IMiningLpPool(poolAddress).getMortgageNum(_account);
        if (mortgageNum >= threshold && rank == 0) {
            quota = whiteListQuota;
            availableAuota = whiteListQuota;
        }

        return (proportion, obtain, exchange, retrievable, balance, quota, availableAuota);
    }

    function getExchangePoolDetails() public view returns (
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        return (
            lpAddress,
            lpQuantitySold,
            totalIssuance,
            startTime,
            endTime,
            claimTime,
            fundRaisingAddress,
            totalFundRaising,
            exchangeRate[1],
            exchangeRate[2],
            totalAmountInvested
        );
    }

    function remainingTime(uint8 _timeType) public view returns (uint256) {
        if (_timeType == 0) {
            if (startTime > 0 && block.timestamp <= startTime) {
                return startTime.sub(block.timestamp);
            } else {
                return 0;
            }
        } else {
            if (endTime > 0 && block.timestamp <= endTime) {
                return endTime.sub(block.timestamp);
            } else {
                return 0;
            }
        }
    }

    function balanceOfByUser(address _account) public view returns (uint, uint) {
        return (IERC20(lpAddress).balanceOf(_account), IERC20(fundRaisingAddress).balanceOf(_account));
    }

}
