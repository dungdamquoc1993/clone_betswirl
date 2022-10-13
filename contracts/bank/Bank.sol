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

contract Bank is AccessControlEnumerable {
    using SafeERC20 for IERC20;

    enum UpkeepActions {
        DistributePartnerHouseEdge
    }

    struct HouseEdgeSplit {
        uint16 team;
        uint16 dividend;
        uint256 dividendAmount;
        uint256 teamAmount;
    }

    struct Token {
        bool allowed;
        bool paused;
        uint16 balanceRisk;
        uint64 VRFSubId;
        HouseEdgeSplit houseEdgeSplit;
        uint256 priceOfToken;
        address lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accEBetPerLpToken;
        uint256 minBetAmount;
    }

    struct TokenMetadata {
        uint8 decimals;
        address tokenAddress;
        string name;
        string symbol;
        Token token;
    }

    struct PartnerInfo {
        uint256 amountOfLp;
        uint256 rewardDebt;
    }

    struct Bet {
        uint256 betAmount;
    }

    EqualBetsToken public eBetToken;

    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    uint256 public totalAllocPoint = 0;

    uint256 public startBlock;

    uint256 public eBetPerBlock;

    mapping(uint256 => mapping(address => PartnerInfo)) public partnerInfo;

    address[] public partnerAddresses;

    uint256 private _tokensCount;

    mapping(uint256 => address) private _tokensList;

    mapping(address => Token) public tokens;

    address public devaddr;

    event AddToken(address token);

    event SetBalanceRisk(address indexed token, uint16 balanceRisk);

    event SetAllowedToken(address indexed token, bool allowed);

    event SetTokenVRFSubId(address indexed token, uint64 subId);

    event SetPausedToken(address indexed token, bool paused);

    event Deposit(
        uint256 indexed pid,
        address partner,
        uint256 amount,
        uint256 lpMintAmount
    );

    event Withdraw(uint256 indexed pid, address partner, uint256 amount);

    event SetTokenHouseEdgeSplit(
        address indexed token,
        uint16 dividend,
        uint16 team
    );

    event UpdatePriceOfToken(address token, uint256 priceOfToken);

    event Payout(address indexed token, uint256 newBalance, uint256 profit);

    event CashIn(address indexed token, uint256 newBalance, uint256 amount);

    event SetAllocPoint(
        address _tokenAddress,
        uint256 _newAllocPoint,
        uint256 _totalAllocPoint
    );

    event AllocateHouseEdgeAmount(
        address token,
        uint256 dividendAmount,
        uint256 teamAmount
    );
    event WithdrawDividend(
        address userAddres,
        address tokenAddress,
        uint256 amount
    );
    event WithdrawTeamAmount(
        address teamAddress,
        address tokenAddress,
        uint256 amount
    );

    error TokenExists();
    error WrongHouseEdgeSplit(uint16 splitSum);
    error AccessDenied();
    error WrongAddress();
    error TokenNotPaused();
    error TokenHasPendingBets();

    constructor(
        uint256 _eBetPerBlock,
        address _devAddr,
        EqualBetsToken _eBetToken,
        uint256 _startBlock
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        eBetPerBlock = _eBetPerBlock;

        setDevAddress(_devAddr);

        eBetToken = _eBetToken;

        startBlock = _startBlock;
    }

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "UniswapV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function _safeEBetTransfer(address _to, uint256 _amount) private {
        uint256 eBetBal = eBetToken.balanceOf(address(this));
        if (_amount > eBetBal) {
            eBetToken.transfer(_to, eBetBal);
        } else {
            eBetToken.transfer(_to, _amount);
        }
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

    function addToken(
        address token,
        uint256 _allocPoint,
        uint256 _priceOfToken
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
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
        _token.priceOfToken = _priceOfToken;
        _token.accEBetPerLpToken = 0;
        _tokensList[_tokensCount] = token;
        _tokensCount += 1;
        emit AddToken(token);
    }

    function updatePriceOfToken(address tokenAddress) private {
        Token storage token = tokens[tokenAddress];
        uint256 totalLpBalance = IBankLPToken(token.lpToken).totalSupply();
        uint256 bankTokenBalance = getBalance(tokenAddress);

        token.priceOfToken = bankTokenBalance > 0 && totalLpBalance > 0
            ? (totalLpBalance * 1e18) / bankTokenBalance
            : token.priceOfToken;
        emit UpdatePriceOfToken(tokenAddress, token.priceOfToken);
    }

    // update accEBetPerLpToken, lastRewardBlock
    function updateToken(uint256 _pid) public payable {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        if (block.number <= token.lastRewardBlock) {
            return;
        }
        uint256 totalLpBalance = IBankLPToken(token.lpToken).totalSupply();
        if (totalLpBalance == 0) {
            token.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(token.lastRewardBlock, block.number);
        uint256 eBetReward = (multiplier * eBetPerBlock * token.allocPoint) /
            totalAllocPoint;
        eBetToken.mint(devaddr, eBetReward / 10);
        eBetToken.mint(address(this), eBetReward);
        token.accEBetPerLpToken =
            token.accEBetPerLpToken +
            (eBetReward * 1e18) /
            totalLpBalance;
        token.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount) external payable lock {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        PartnerInfo storage partner = partnerInfo[_pid][_msgSender()];

        if (!exists(_msgSender(), partnerAddresses)) {
            partnerAddresses.push(_msgSender());
        }

        updateToken(_pid); // update accEBetPerLpToken
        if (partner.amountOfLp > 0) {
            uint256 pendingReward = ((partner.amountOfLp *
                token.accEBetPerLpToken) / 1e18) - partner.rewardDebt;
            if (pendingReward > 0) {
                _safeEBetTransfer(_msgSender(), pendingReward);
            }
        }

        partner.rewardDebt =
            (partner.amountOfLp * token.accEBetPerLpToken) /
            1e18;

        if (!_isGasToken(tokenAddress)) {
            IERC20(tokenAddress).safeTransferFrom(
                address(_msgSender()),
                address(this),
                _amount
            );
        } else {
            _amount = msg.value;
        }

        uint256 lpMintAmount = (_amount * token.priceOfToken) / 1e18;
        IBankLPToken(token.lpToken).mint(_msgSender(), lpMintAmount);
        partner.amountOfLp = partner.amountOfLp + lpMintAmount;

        updatePriceOfToken(tokenAddress); // update token.priceOfToken need totalToken and totalLP to update correctly

        require(lpMintAmount > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        emit Deposit(_pid, _msgSender(), _amount, lpMintAmount);
    }

    function withdraw(
        uint256 _pid,
        uint256 lpAmount // must approve before call this function
    ) public payable lock {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        PartnerInfo storage partner = partnerInfo[_pid][_msgSender()];

        if (!token.paused) {
            revert TokenNotPaused();
        }

        uint256 roleMemberCount = getRoleMemberCount(GAME_ROLE);
        for (uint256 i; i < roleMemberCount; i++) {
            if (
                IGame(getRoleMember(GAME_ROLE, i)).hasPendingBets(tokenAddress)
            ) {
                revert TokenHasPendingBets();
            }
        }

        updateToken(_pid); // update accEBetPerLpToken
        uint256 userLpBalance = IBankLPToken(token.lpToken).balanceOf(
            _msgSender()
        );
        require(
            lpAmount <= userLpBalance && lpAmount <= partner.amountOfLp,
            "INSUFFICIENT_LIQUIDITY_TO_WITHDRAW"
        );

        IBankLPToken(token.lpToken).transferFrom(
            _msgSender(),
            address(this),
            lpAmount
        );

        uint256 withdrawAmount = (lpAmount * 1e18) / token.priceOfToken;
        uint256 bankTokenBalance = getBalance(tokenAddress);
        require( // 0.01% slipage
            bankTokenBalance >= withdrawAmount,
            "bank balance insufficient"
        );

        uint256 pendingReward = ((partner.amountOfLp *
            token.accEBetPerLpToken) / 1e18) - partner.rewardDebt;
        if (pendingReward > 0) {
            _safeEBetTransfer(_msgSender(), pendingReward);
        }

        partner.rewardDebt =
            (partner.amountOfLp * token.accEBetPerLpToken) /
            1e18;

        if (withdrawAmount > 0) {
            partner.amountOfLp = partner.amountOfLp - lpAmount;
            IBankLPToken(token.lpToken).burn(address(this), lpAmount);
            _safeTransfer(_msgSender(), tokenAddress, withdrawAmount);
        }

        if (exists(_msgSender(), partnerAddresses) && partner.amountOfLp == 0) {
            // delete partner from list partner address
            for (uint256 i = 0; i < partnerAddresses.length; i++) {
                if (partnerAddresses[i] == _msgSender()) {
                    partnerAddresses[i] = partnerAddresses[
                        partnerAddresses.length - 1
                    ];
                    partnerAddresses.pop();
                }
            }
        }

        updatePriceOfToken(tokenAddress); // update token.priceOfToken need totalToken and totalLP to update correctly

        emit Withdraw(_pid, _msgSender(), withdrawAmount);
    }

    function claimReward(uint256 _pid, address userAddress) public lock {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        PartnerInfo storage partner = partnerInfo[_pid][userAddress];
        updateToken(_pid); // update token.accEBetPerLpToken

        uint256 pendingReward = ((partner.amountOfLp *
            token.accEBetPerLpToken) / 1e18) - partner.rewardDebt;
        if (pendingReward > 0) {
            _safeEBetTransfer(userAddress, pendingReward);
        }
        partner.rewardDebt =
            (partner.amountOfLp * token.accEBetPerLpToken) /
            1e18;
    }

    function pendingEbet(uint256 _pid, address userAddress)
        public
        view
        returns (uint256)
    {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        PartnerInfo storage partner = partnerInfo[_pid][userAddress];
        uint256 accEBetPerLpToken = token.accEBetPerLpToken;
        uint256 totalLpBalance = IBankLPToken(token.lpToken).totalSupply();
        if (block.number > token.lastRewardBlock && totalLpBalance != 0) {
            uint256 multiplier = getMultiplier(
                token.lastRewardBlock,
                block.number
            );
            uint256 eBetReward = (multiplier *
                eBetPerBlock *
                token.allocPoint) / totalAllocPoint;
            accEBetPerLpToken =
                accEBetPerLpToken +
                (eBetReward * 1e18) /
                totalLpBalance;
        }
        console.log(accEBetPerLpToken);

        uint256 pendingReward = ((partner.amountOfLp * accEBetPerLpToken) /
            1e18) - partner.rewardDebt;
        return pendingReward;
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

    function _allocateHouseEdge(address token, uint256 fees) private {
        HouseEdgeSplit storage tokenHouseEdge = tokens[token].houseEdgeSplit;

        uint256 teamAmount = (fees * tokenHouseEdge.team) / 10000;
        tokenHouseEdge.teamAmount += teamAmount; // 50%

        uint256 dividendAmount = (fees * tokenHouseEdge.dividend) / 10000;
        tokenHouseEdge.dividendAmount += dividendAmount; // 50%
        emit AllocateHouseEdgeAmount(token, dividendAmount, teamAmount);
    }

    // onlyRole(GAME_ROLE)
    function payout(
        address payable user,
        uint256 _pid,
        uint256 _profit,
        uint256 fees
    ) external payable {
        // when user win betamount will be send by Game contract
        // profitamount will be send by bank
        // profitfee will keep in bank contract
        address tokenAddress = _tokensList[_pid];
        _allocateHouseEdge(tokenAddress, fees);

        _safeTransfer(user, tokenAddress, _profit);
        updatePriceOfToken(tokenAddress);

        emit Payout(tokenAddress, getBalance(tokenAddress), _profit);
    }

    // onlyRole(GAME_ROLE)
    function cashIn(
        uint256 _pid,
        uint256 amount,
        uint256 fees
    ) external payable {
        address tokenAddress = _tokensList[_pid];
        _allocateHouseEdge(tokenAddress, fees);
        updatePriceOfToken(tokenAddress);
        emit CashIn(
            tokenAddress,
            getBalance(tokenAddress),
            _isGasToken(tokenAddress) ? msg.value : amount
        );
    }

    function withdrawDividend(uint256 _pid) public {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        HouseEdgeSplit storage tokenHouseEdge = token.houseEdgeSplit;
        uint256 dividendAmount = tokenHouseEdge.dividendAmount;
        uint256 totalLpSupply = IBankLPToken(token.lpToken).totalSupply();
        for (uint256 i = 0; i < partnerAddresses.length; i++) {
            address partnerAddress = partnerAddresses[i];
            PartnerInfo storage partner = partnerInfo[_pid][partnerAddress];
            uint256 partnerLpBalance = partner.amountOfLp;

            uint256 withdrawAmount = (dividendAmount * partnerLpBalance) /
                totalLpSupply;
            _safeTransfer(partnerAddress, tokenAddress, withdrawAmount);
        }
        delete tokenHouseEdge.dividendAmount;

        emit WithdrawDividend(_msgSender(), tokenAddress, dividendAmount);
    }

    function withdrawTeamAmount(uint256 _pid) public {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        HouseEdgeSplit storage tokenHouseEdge = token.houseEdgeSplit;
        uint256 teamAmount = tokenHouseEdge.teamAmount;

        _safeTransfer(devaddr, tokenAddress, teamAmount);
        delete tokenHouseEdge.teamAmount;

        emit WithdrawTeamAmount(devaddr, tokenAddress, teamAmount);
    }

    function _isGasToken(address token) private pure returns (bool) {
        return token == address(0);
    }

    function setDevAddress(address _devAddr)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_devAddr != address(0), "dev address is invalid");
        devaddr = _devAddr;
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
        uint16 team,
        uint16 dividend
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint16 splitSum = team + dividend;
        if (splitSum != 10000) {
            revert WrongHouseEdgeSplit(splitSum);
        }

        HouseEdgeSplit storage tokenHouseEdge = tokens[token].houseEdgeSplit;
        tokenHouseEdge.dividend = dividend;
        tokenHouseEdge.team = team;

        emit SetTokenHouseEdgeSplit(token, dividend, team);
    }

    function setTokenVRFSubId(address token, uint64 subId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].VRFSubId = subId;
        emit SetTokenVRFSubId(token, subId);
    }

    function setTokenMinBetAmount(address token, uint256 tokenMinBetAmount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].minBetAmount = tokenMinBetAmount;
    }

    function getPriceOfToken(uint256 _pid) public view returns (uint256) {
        address tokenAddress = _tokensList[_pid];
        Token storage token = tokens[tokenAddress];
        return token.priceOfToken;
    }

    function getMaxBetAmount(address token, uint256 multiplier)
        external
        view
        returns (uint256)
    {
        return (getBalance(token) * tokens[token].balanceRisk) / multiplier;
    }

    function getVRFSubId(address token) external view returns (uint64) {
        return tokens[token].VRFSubId;
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
            tokenHouseEdgeSplit.dividendAmount -
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

    function getMultiplier(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to - _from;
    }

    function exists(address checkAddress, address[] memory addresses)
        public
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == checkAddress) {
                return true;
            }
        }
        return false;
    }

    function isAllowedToken(address tokenAddress) external view returns (bool) {
        Token memory token = tokens[tokenAddress];
        return token.allowed && !token.paused;
    }
}
