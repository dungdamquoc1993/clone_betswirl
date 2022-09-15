// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "../library/SafeERC20.sol";
import "../interface/IERC20.sol";
import "../interface/IERC20Metadata.sol";
import "../interface/IGame.sol";
import "../abstract/Multicall.sol";
import "../abstract/AccessControlEnumerable.sol";
import "../BankLPToken.sol";
import "../interface/IBankLPToken.sol";
import "../EqualBetsToken.sol";

contract Bank is AccessControlEnumerable, Multicall {
    using SafeERC20 for IERC20;

    enum UpkeepActions {
        DistributePartnerHouseEdge
    }

    struct HouseEdgeSplit {
        uint16 bank;
        uint16 treasury;
        uint16 team;
        uint256 partnerAmount;
        uint256 treasuryAmount;
        uint256 teamAmount;
    }

    struct Token {
        bool allowed;
        bool paused;
        uint16 balanceRisk;
        uint64 VRFSubId;
        uint256 minBetAmount;
        uint256 minPartnerTransferAmount;
        HouseEdgeSplit houseEdgeSplit;
        uint256 lpTokenPerToken;
        address lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accEBetPerShare;
    }

    struct TokenMetadata {
        uint8 decimals;
        address tokenAddress;
        string name;
        string symbol;
        Token token;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    EqualBetsToken public eBetToken;

    address public immutable treasury;

    address public teamWallet;

    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    uint256 public totalAllocPoint = 0;

    uint256 public startBlock;

    uint256 public eBetPerBlock;

    uint256 private _tokensCount;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    mapping(uint256 => address) private _tokensList;

    mapping(address => Token) public tokens;

    address public devaddr;

    event SetTeamWallet(address teamWallet);

    event AddToken(address token);

    event SetBalanceRisk(address indexed token, uint16 balanceRisk);

    event SetAllowedToken(address indexed token, bool allowed);

    event SetTokenMinBetAmount(address indexed token, uint256 minBetAmount);

    event SetTokenVRFSubId(address indexed token, uint64 subId);

    event SetPausedToken(address indexed token, bool paused);

    event SetMinPartnerTransferAmount(
        address indexed token,
        uint256 minPartnerTransferAmount
    );

    event Deposit(
        uint256 indexed pid,
        address user,
        uint256 amount,
        uint256 lpMintAmount
    );

    event Withdraw(uint256 indexed pid, address user, uint256 amount);

    event SetTokenHouseEdgeSplit(
        address indexed token,
        uint16 bank,
        uint16 treasury,
        uint16 team
    );
    event HouseEdgeDistribution(
        address indexed token,
        uint256 treasuryAmount,
        uint256 teamAmount
    );
    event HouseEdgePartnerDistribution(
        address indexed token,
        uint256 partnerAmount
    );

    event SetLpTokenPerToken(address token, uint256 lpTokenPerToken);
    event AllocateHouseEdgeAmount(
        address indexed token,
        uint256 bank,
        uint256 treasury,
        uint256 team
    );
    event Payout(address indexed token, uint256 newBalance, uint256 profit);

    event CashIn(address indexed token, uint256 newBalance, uint256 amount);

    event SetAllocPoint(
        address _tokenAddress,
        uint256 _newAllocPoint,
        uint256 _totalAllocPoint
    );

    error TokenExists();
    error WrongHouseEdgeSplit(uint16 splitSum);
    error AccessDenied();
    error WrongAddress();
    error TokenNotPaused();
    error TokenHasPendingBets();

    constructor(
        address treasuryAddress,
        address teamWalletAddress,
        uint256 _eBetPerBlock,
        address _devAddr,
        EqualBetsToken _eBetToken
    ) {
        if (treasuryAddress == address(0)) {
            revert WrongAddress();
        }
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        treasury = treasuryAddress;

        setTeamWallet(teamWalletAddress);

        eBetPerBlock = _eBetPerBlock;

        devaddr = _devAddr;

        eBetToken = _eBetToken;
    }

    function _safeEBetTransfer(address _to, uint256 _amount) internal {
        uint256 eBetBal = eBetToken.balanceOf(address(this));
        if (_amount > eBetBal) {
            eBetToken.transfer(_to, eBetBal);
        } else {
            eBetToken.transfer(_to, _amount);
        }
    }

    function _isGasToken(address token) private pure returns (bool) {
        return token == address(0);
    }

    function _safeTransfer(
        address user,
        address token,
        uint256 amount
    ) private {
        if (_isGasToken(token)) {
            payable(user).transfer(amount);
        } else {
            IERC20(token).safeTransfer(user, amount);
        }
    }

    function setDevAddress(address _devAddr)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_devAddr != address(0), "dev address is invalid");
        devaddr = _devAddr;
    }

    function setStartBlock(uint256 _startBlock)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            _startBlock > block.number,
            "start block must be greater current block"
        );
        startBlock = _startBlock;
    }

    function setAllocPoint(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_withUpdate) {
            // massUpdatePools();
        }
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        uint256 prevAllocPoint = token.allocPoint;
        token.allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint - prevAllocPoint + _allocPoint;
        }
        emit SetAllocPoint(tokenAddress, _allocPoint, totalAllocPoint);
    }

    function setLpTokenPerToken(address tokenAddress, uint256 lpTokenPerToken)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        Token storage token = tokens[tokenAddress];
        require(
            token.allowed && !token.paused,
            "token is not allowed or paused is true"
        );
        token.lpTokenPerToken = lpTokenPerToken;
        emit SetLpTokenPerToken(tokenAddress, lpTokenPerToken);
    }

    function addToken(address token, uint256 _allocPoint)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            token != address(eBetToken),
            "cannot add ebet token for liquidity"
        );

        if (_tokensCount != 0) {
            for (uint8 i; i < _tokensCount; i++) {
                if (_tokensList[i] == token) {
                    revert TokenExists();
                }
            }
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;

        bytes memory bytecode = type(BankLPToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token));
        address lpAddress;
        assembly {
            lpAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IBankLPToken(lpAddress).initialize();
        Token storage _token = tokens[token];
        _token.lpToken = lpAddress;
        _token.allocPoint = _allocPoint;
        _token.lastRewardBlock = lastRewardBlock;
        _token.accEBetPerShare = 0;
        _tokensList[_tokensCount] = token;
        _tokensCount += 1;
        emit AddToken(token);
    }

    function updateToken(uint256 _pid, bool isDeposit) public payable {
        // update accEBetPerShare, lastRewardBlock
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        if (block.number <= token.lastRewardBlock) {
            return;
        }
        uint256 bankLPSupplyBalance;
        if (_isGasToken(tokenAddress)) {
            bankLPSupplyBalance = isDeposit
                ? address(this).balance - msg.value
                : address(this).balance;
        } else {
            bankLPSupplyBalance = IERC20(tokenAddress).balanceOf(address(this));
        }
        if (bankLPSupplyBalance == 0) {
            token.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(token.lastRewardBlock, block.number);
        uint256 eBetReward = (multiplier * eBetPerBlock * token.allocPoint) /
            totalAllocPoint;
        eBetToken.mint(devaddr, eBetReward / 10);
        eBetToken.mint(address(this), eBetReward);
        token.accEBetPerShare =
            token.accEBetPerShare +
            (eBetReward * 1e18) /
            bankLPSupplyBalance;
        token.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount) external payable {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        UserInfo storage user = userInfo[_pid][_msgSender()];

        updateToken(_pid, true);

        if (user.amount > 0) {
            uint256 pendingReward = ((user.amount * token.accEBetPerShare) /
                1e18) - user.rewardDebt;
            if (pendingReward > 0) {
                _safeEBetTransfer(_msgSender(), pendingReward);
            }
        }
        if (_isGasToken(tokenAddress)) {
            _amount = msg.value;
            user.amount = user.amount + _amount;
        } else {
            if (_amount > 0) {
                IERC20(tokenAddress).safeTransferFrom(
                    address(_msgSender()),
                    address(this),
                    _amount
                );
                user.amount = user.amount + _amount;
            }
        }
        user.rewardDebt = (user.amount * token.accEBetPerShare) / 1e18;

        uint256 liquidity = token.lpTokenPerToken * _amount;
        IBankLPToken(token.lpToken).mint(_msgSender(), liquidity);
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        emit Deposit(_pid, _msgSender(), _amount, liquidity);
    }

    function withdraw(
        uint256 _pid,
        uint256 lpAmount // must approve before call this function
    ) public payable {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        uint256 userLpAmountBal = IBankLPToken(token.lpToken).balanceOf(
            _msgSender()
        );
        require(
            lpAmount <= userLpAmountBal,
            "INSUFFICIENT_LIQUIDITY_TO_WITHDRAW"
        );

        IBankLPToken(token.lpToken).transferFrom(
            _msgSender(),
            address(this),
            lpAmount
        );
        uint256 bankLPTokenTotalSupply = IBankLPToken(token.lpToken)
            .totalSupply();
        uint256 bankLPSupplyBalance;
        if (_isGasToken(tokenAddress)) {
            bankLPSupplyBalance = address(this).balance;
        } else {
            bankLPSupplyBalance = IERC20(tokenAddress).balanceOf(address(this));
        }
        uint256 withdrawAmount = (lpAmount * bankLPSupplyBalance) /
            bankLPTokenTotalSupply;

        require(user.amount >= withdrawAmount, "withdraw: not good");
        require(
            bankLPSupplyBalance >= withdrawAmount,
            "bank balance insufficient"
        );

        updateToken(_pid, false); // update accEBetPerShare
        uint256 pendingReward = ((user.amount * token.accEBetPerShare) / 1e18) -
            user.rewardDebt;
        if (pendingReward > 0) {
            _safeEBetTransfer(_msgSender(), pendingReward);
        }
        if (withdrawAmount > 0) {
            user.amount = user.amount - withdrawAmount;
            IBankLPToken(token.lpToken).burn(address(this), lpAmount);
            _safeTransfer(_msgSender(), tokenAddress, withdrawAmount);
        }
        user.rewardDebt = (user.amount * token.accEBetPerShare) / 1e18;

        emit Withdraw(_pid, _msgSender(), withdrawAmount);
    }

    function pendingEBet(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accEBetPerShare = token.accEBetPerShare;
        uint256 bankLPSupplyBalance;
        if (_isGasToken(tokenAddress)) {
            bankLPSupplyBalance = address(this).balance;
        } else {
            bankLPSupplyBalance = IERC20(tokenAddress).balanceOf(address(this));
        }
        if (block.number > token.lastRewardBlock && bankLPSupplyBalance != 0) {
            uint256 multiplier = getMultiplier(
                token.lastRewardBlock,
                block.number
            );
            uint256 eBetReward = (multiplier *
                eBetPerBlock *
                token.allocPoint) / totalAllocPoint;
            accEBetPerShare =
                accEBetPerShare +
                (eBetReward * 1e18) /
                bankLPSupplyBalance;
        }
        return ((user.amount * accEBetPerShare) / 1e18) - user.rewardDebt;
    }

    function claimReward(uint256 _pid, uint256 _amount) public {
        require(_amount > 0, "cannot claim 0 reward");
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        updateToken(_pid, false); // update accEBetPerShare
        uint256 pending = ((user.amount * token.accEBetPerShare) / 1e18) -
            (user.rewardDebt);
        uint256 eBetBal = eBetToken.balanceOf(address(this));
        require(_amount <= pending, "Insuficent reward balance");
        require(
            _amount <= eBetBal,
            "amount cannot be greater than Bank Balance"
        );
        user.rewardDebt = user.rewardDebt + _amount;
        _safeEBetTransfer(_msgSender(), pending);
    }

    function setBalanceRisk(address token, uint16 balanceRisk)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].balanceRisk = balanceRisk;
        emit SetBalanceRisk(token, balanceRisk);
    }

    function setAllowedToken(address token, bool allowed)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].allowed = allowed;
        emit SetAllowedToken(token, allowed);
    }

    function setPausedToken(address token, bool paused)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].paused = paused;
        emit SetPausedToken(token, paused);
    }

    function setHouseEdgeSplit(
        address token,
        uint16 bank,
        uint16 _treasury,
        uint16 team
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint16 splitSum = bank + team + _treasury;
        if (splitSum != 10000) {
            revert WrongHouseEdgeSplit(splitSum);
        }

        HouseEdgeSplit storage tokenHouseEdge = tokens[token].houseEdgeSplit;
        tokenHouseEdge.bank = bank;
        tokenHouseEdge.treasury = _treasury;
        tokenHouseEdge.team = team;

        emit SetTokenHouseEdgeSplit(token, bank, _treasury, team);
    }

    function setTokenMinBetAmount(address token, uint256 tokenMinBetAmount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].minBetAmount = tokenMinBetAmount;
        emit SetTokenMinBetAmount(token, tokenMinBetAmount);
    }

    function setTokenVRFSubId(address token, uint64 subId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].VRFSubId = subId;
        emit SetTokenVRFSubId(token, subId);
    }

    function payout(
        address payable user,
        address token,
        uint256 profit,
        uint256 fees
    ) external payable onlyRole(GAME_ROLE) {
        {
            HouseEdgeSplit storage tokenHouseEdge = tokens[token]
                .houseEdgeSplit;

            uint256 bankAmount = (fees * tokenHouseEdge.bank) / 10000;

            uint256 treasuryAmount = (fees * tokenHouseEdge.treasury) / 10000;
            tokenHouseEdge.treasuryAmount += treasuryAmount;

            uint256 teamAmount = (fees * tokenHouseEdge.team) / 10000;
            tokenHouseEdge.teamAmount += teamAmount;

            emit AllocateHouseEdgeAmount(
                token,
                bankAmount,
                treasuryAmount,
                teamAmount
            );
        }

        // Pay the user
        _safeTransfer(user, token, profit);
        emit Payout(token, getBalance(token), profit);
    }

    function cashIn(address tokenAddress, uint256 amount)
        external
        payable
        onlyRole(GAME_ROLE)
    {
        emit CashIn(
            tokenAddress,
            getBalance(tokenAddress),
            _isGasToken(tokenAddress) ? msg.value : amount
        );
    }

    function getTokens() external view returns (TokenMetadata[] memory) {
        TokenMetadata[] memory _tokens = new TokenMetadata[](_tokensCount);
        for (uint8 i; i < _tokensCount; i++) {
            address tokenAddress = _tokensList[i];
            Token memory token = tokens[tokenAddress];
            if (_isGasToken(tokenAddress)) {
                _tokens[i] = TokenMetadata({
                    decimals: 18,
                    tokenAddress: tokenAddress,
                    name: "ETH",
                    symbol: "ETH",
                    token: token
                });
            } else {
                IERC20Metadata erc20Metadata = IERC20Metadata(tokenAddress);
                _tokens[i] = TokenMetadata({
                    decimals: erc20Metadata.decimals(),
                    tokenAddress: tokenAddress,
                    name: erc20Metadata.name(),
                    symbol: erc20Metadata.symbol(),
                    token: token
                });
            }
        }
        return _tokens;
    }

    function getMinBetAmount(address token)
        external
        view
        returns (uint256 minBetAmount)
    {
        minBetAmount = tokens[token].minBetAmount;
        if (minBetAmount == 0) {
            minBetAmount = 10000;
        }
    }

    function getMaxBetAmount(address token, uint256 multiplier)
        external
        view
        returns (uint256)
    {
        return (getBalance(token) * tokens[token].balanceRisk) / multiplier;
    }

    function isAllowedToken(address tokenAddress) external view returns (bool) {
        Token memory token = tokens[tokenAddress];
        return token.allowed && !token.paused;
    }

    function getVRFSubId(address token) external view returns (uint64) {
        return tokens[token].VRFSubId;
    }

    function setTeamWallet(address _teamWallet)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_teamWallet == address(0)) {
            revert WrongAddress();
        }
        teamWallet = _teamWallet;
        emit SetTeamWallet(teamWallet);
    }

    function withdrawHouseEdgeAmount(address tokenAddress) public {
        HouseEdgeSplit storage tokenHouseEdge = tokens[tokenAddress]
            .houseEdgeSplit;
        uint256 treasuryAmount = tokenHouseEdge.treasuryAmount;
        uint256 teamAmount = tokenHouseEdge.teamAmount;
        if (treasuryAmount != 0) {
            delete tokenHouseEdge.treasuryAmount;
            _safeTransfer(treasury, tokenAddress, treasuryAmount);
        }
        if (teamAmount != 0) {
            delete tokenHouseEdge.teamAmount;
            _safeTransfer(teamWallet, tokenAddress, teamAmount);
        }
        if (treasuryAmount != 0 || teamAmount != 0) {
            emit HouseEdgeDistribution(
                tokenAddress,
                treasuryAmount,
                teamAmount
            );
        }
    }

    function getBalance(address token) public view returns (uint256) {
        uint256 balance;
        if (_isGasToken(token)) {
            balance = address(this).balance;
        } else {
            balance = IERC20(token).balanceOf(address(this));
        }
        HouseEdgeSplit memory tokenHouseEdgeSplit = tokens[token]
            .houseEdgeSplit;
        return
            balance -
            tokenHouseEdgeSplit.partnerAmount -
            tokenHouseEdgeSplit.treasuryAmount -
            tokenHouseEdgeSplit.teamAmount;
    }

    function getLpTokenAddress(address bank, address token)
        external
        pure
        returns (address lpAddress)
    {
        lpAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            bank,
                            keccak256(abi.encodePacked(token)),
                            hex"d71df1611a15ebbf99b4369d68b71a1463e6f93dc304c00c224fc5cf8d9f13bd" // init code hash
                        )
                    )
                )
            )
        );
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to - _from;
    }
}

// Constructor => (address treasuryAddress, address teamWalletAddress) setup default role as DEFAULT_ADMIN_ROLE

// ROLE require
// Deposit => 						external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender)
// Withdrawn => 					public onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender)

// addToken => 					    external onlyRole(DEFAULT_ADMIN_ROLE)

// setAllowedToken => 				external onlyRole(DEFAULT_ADMIN_ROLE)
// setPausedToken => 				external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender) false
// setBalanceRisk => 				external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender) 2
// setTokenVRFSubId => 			    external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender)
// setTokenPartner => 				external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender)
// setTokenMinBetAmount => 	    	external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender)
// setMinPartnerTransferAmount =>  external onlyTokenOwner(DEFAULT_ADMIN_ROLE, token) => _checkRole(DEFAULT_ADMIN_ROLE, sender) 2

// setHouseEdgeSplit => 			external onlyRole(DEFAULT_ADMIN_ROLE)
// setTeamWallet => 				public onlyRole(DEFAULT_ADMIN_ROLE)

// payout => 						external onlyRole(GAME_ROLE)
// cashIn => 						external onlyRole(GAME_ROLE)
// harvest => 						external onlyRole(SWIRLMASTER_ROLE)

// _safeTransfer => private noRole
// _isGasToken => private noRole
// getTokens => external noRole
// getMinBetAmount => external noRole
// getMaxBetAmount => external noRole
// getVRFSubId => external noRole
// getTokenOwner => external noRole

// withdrawHouseEdgeAmount => public noRole
// withdrawPartnerAmount => public noRole
// getBalance => public noRole

// performUpkeep => external noRole
// checkUpkeep => external noRole (Chainlink)
