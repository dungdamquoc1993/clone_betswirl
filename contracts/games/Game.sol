// SPDX-License-Identifier: UNLICENSED
import "../abstract/Multicall.sol";
import "../abstract/ReentrancyGuard.sol";
import "../openzepplin/Pausable.sol";
import "../openzepplin/Ownable.sol";
import "../chainLink/VRFConsumerBaseV2.sol";

// import "../interface/IERC20Permit.sol";
import "../library/SafeERC20.sol";
import "../interface/IERC20.sol";
import "../interface/IBank.sol";
import "../chainLink/AggregatorV3Interface.sol";
import "../chainLink/IVRFCoordinatorV2.sol";

import "hardhat/console.sol";

pragma solidity ^0.8.1;

abstract contract Game is
    Ownable,
    Pausable,
    Multicall,
    VRFConsumerBaseV2,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    struct Bet {
        bool resolved;
        address payable user;
        address token;
        uint256 id;
        uint256 amount;
        uint256 blockNumber;
        uint256 payout;
        uint256 vrfCost;
    }

    /// @param houseEdge House edge rate.
    /// @param pendingCount Number of pending bets.
    /// @param VRFCallbackGasLimit How much gas is needed in the Chainlink VRF callback.
    /// @param VRFFees Chainlink's VRF collected fees amount.
    struct Token {
        uint16 houseEdge;
        uint64 pendingCount;
        uint32 VRFCallbackGasLimit;
        uint256 VRFFees;
    }

    /// @param requestConfirmations How many confirmations the Chainlink node should wait before responding.
    /// @param numRandomWords How many random words is needed to resolve a game's bet.
    /// @param keyHash Hash of the public key used to verify the VRF proof.
    /// @param chainlinkCoordinator Reference to the VRFCoordinatorV2 deployed contract.
    struct ChainlinkConfig {
        uint16 requestConfirmations;
        uint16 numRandomWords;
        bytes32 keyHash;
        IVRFCoordinatorV2 chainlinkCoordinator;
    }

    ChainlinkConfig private _chainlinkConfig;

    AggregatorV3Interface private immutable _LINK_ETH_feed;

    mapping(uint256 => Bet) public bets;

    mapping(address => uint256[]) internal _userBets;

    mapping(address => Token) public tokens;

    IBank public bank;

    /// @param bank Address of the bank contract.
    event SetBank(address bank);

    /// @param token Address of the token.
    /// @param houseEdge House edge rate.
    event SetHouseEdge(address indexed token, uint16 houseEdge);

    /// @param token Address of the token.
    /// @param callbackGasLimit New Chainlink VRF callback gas limit.
    event SetVRFCallbackGasLimit(
        address indexed token,
        uint32 callbackGasLimit
    );

    /// @param requestConfirmations How many confirmations the Chainlink node should wait before responding.
    /// @param keyHash Hash of the public key used to verify the VRF proof.
    event SetChainlinkConfig(uint16 requestConfirmations, bytes32 keyHash);

    /// @param id The bet ID.
    /// @param amount Number of tokens failed to transfer.
    /// @param reason The reason provided by the external call.
    event BetAmountTransferFail(uint256 id, uint256 amount, string reason);

    /// @param id The bet ID.
    /// @param amount Number of tokens failed to transfer.
    /// @param reason The reason provided by the external call.
    event BetAmountFeeTransferFail(uint256 id, uint256 amount, string reason);

    /// @param id The bet ID.
    /// @param amount Number of tokens failed to transfer.
    /// @param reason The reason provided by the external call.
    event BetProfitTransferFail(uint256 id, uint256 amount, string reason);

    /// @param id The bet ID.
    /// @param amount Number of tokens failed to transfer.
    /// @param reason The reason provided by the external call.
    event BankCashInFail(uint256 id, uint256 amount, string reason);

    /// @param id The bet ID.
    /// @param amount Number of tokens failed to transfer.
    /// @param reason The reason provided by the external call.
    event BankTransferFail(uint256 id, uint256 amount, string reason);

    /// @param id The bet ID.
    /// @param user Address of the gamer.
    /// @param amount Number of tokens refunded.
    event BetRefunded(uint256 id, address user, uint256 amount);

    /// @param id The bet ID.
    /// @param user Address of the gamer.
    /// @param chainlinkVRFCost The bet resolution cost amount.
    event BetCostRefundFail(uint256 id, address user, uint256 chainlinkVRFCost);

    /// @param token Address of the token.
    /// @param amount Number of tokens refunded.
    event DistributeTokenVRFFees(address indexed token, uint256 amount);

    /// @param minBetAmount Bet amount.
    error UnderMinBetAmount(uint256 minBetAmount);

    error NotPendingBet();

    error NotFulfilled();

    error ExcessiveHouseEdge();

    error ForbiddenToken();

    /// @param linkWei LINK/ETH price returned.
    error InvalidLinkWeiPrice(int256 linkWei);

    error WrongGasValueToCoverFee();

    error AccessDenied();

    error InvalidAddress();

    constructor(
        address bankAddress,
        address chainlinkCoordinatorAddress,
        uint16 numRandomWords,
        address LINK_ETH_feedAddress
    ) VRFConsumerBaseV2(chainlinkCoordinatorAddress) {
        if (
            LINK_ETH_feedAddress == address(0) ||
            chainlinkCoordinatorAddress == address(0)
        ) {
            revert InvalidAddress();
        }
        require(
            numRandomWords != 0 && numRandomWords <= 500,
            "Wrong Chainlink NumRandomWords"
        );

        setBank(IBank(bankAddress));
        _chainlinkConfig.chainlinkCoordinator = IVRFCoordinatorV2(
            chainlinkCoordinatorAddress
        );
        _chainlinkConfig.numRandomWords = numRandomWords;
        _LINK_ETH_feed = AggregatorV3Interface(LINK_ETH_feedAddress);
    }

    /// @param token Address of the token.
    /// @param amount From which the fee amount will be calculated.
    /// @return The fee amount.
    function _getFees(address token, uint256 amount)
        private
        view
        returns (uint256)
    {
        return (tokens[token].houseEdge * amount) / 10000;
    }

    /// @param tokenAddress Address of the token.
    /// @param tokenAmount The number of tokens bet.
    /// @param multiplier The bet amount leverage determines the user's profit amount. 10000 = 100% = no profit.
    /// @return A new Bet struct information.
    function _newBet(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 multiplier
    ) internal whenNotPaused nonReentrant returns (Bet memory) {
        if (bank.isAllowedToken(tokenAddress) == false) {
            revert ForbiddenToken();
        }

        address user = msg.sender;
        bool isGasToken = tokenAddress == address(0);
        uint256 fee = isGasToken ? (msg.value - tokenAmount) : msg.value;
        uint256 betAmount = isGasToken ? msg.value - fee : tokenAmount;
        Token storage token = tokens[tokenAddress];

        // Charge user for Chainlink VRF fee.
        {
            uint256 chainlinkVRFCost = getChainlinkVRFCost(tokenAddress);
            if (fee < (chainlinkVRFCost - ((10 * chainlinkVRFCost) / 100))) {
                // 5% slippage.
                revert WrongGasValueToCoverFee();
            }
            token.VRFFees += fee;
        }

        // Bet amount is capped.
        {
            // token,
            // tokenAmount,
            // _getPayout(10000, numbers)
            uint256 minBetAmount = bank.getMinBetAmount(tokenAddress);
            if (betAmount < minBetAmount) {
                revert UnderMinBetAmount(minBetAmount);
            }

            uint256 maxBetAmount = bank.getMaxBetAmount(
                tokenAddress,
                multiplier
            );
            if (betAmount > maxBetAmount) {
                if (isGasToken) {
                    payable(user).transfer(betAmount - maxBetAmount);
                }
                betAmount = maxBetAmount;
            }
        }

        // Create bet
        uint256 id = _chainlinkConfig.chainlinkCoordinator.requestRandomWords(
            _chainlinkConfig.keyHash,
            bank.getVRFSubId(tokenAddress),
            _chainlinkConfig.requestConfirmations,
            token.VRFCallbackGasLimit,
            _chainlinkConfig.numRandomWords
        );
        Bet memory newBet = Bet(
            false,
            payable(user),
            tokenAddress,
            id,
            betAmount,
            block.number,
            0,
            fee
        );
        _userBets[user].push(id);
        bets[id] = newBet;
        token.pendingCount++;

        // If ERC20, transfer the tokens
        if (!isGasToken) {
            IERC20(tokenAddress).safeTransferFrom(
                user,
                address(this),
                betAmount
            );
        }

        return newBet;
    }

    /// @notice Resolves the bet based on the game child contract result.
    /// In case bet is won, the bet amount minus the house edge is transfered to user from the game contract, and the profit is transfered to the user from the Bank.
    /// In case bet is lost, the bet amount is transfered to the Bank from the game contract.
    /// @param bet The Bet struct information.
    /// @param wins Whether the bet is winning.
    /// @param payout What should be sent to the user in case of a won bet. Payout = bet amount + profit amount.
    /// @return The payout amount.
    /// @dev Should not revert as it resolves the bet with the randomness.
    function _resolveBet(
        Bet storage bet,
        bool wins,
        uint256 payout
    ) internal returns (uint256) {
        if (bet.resolved == true || bet.user == address(0)) {
            revert NotPendingBet();
        }
        bet.resolved = true;

        address token = bet.token;
        tokens[token].pendingCount--;

        uint256 betAmount = bet.amount;
        bool isGasToken = bet.token == address(0);
        // Check for the result
        if (wins) {
            address payable user = bet.user;

            uint256 profit = payout - betAmount;
            uint256 betAmountFee = _getFees(token, betAmount);
            uint256 profitFee = _getFees(token, profit);
            uint256 fee = betAmountFee + profitFee;

            payout -= fee;

            uint256 betAmountPayout = betAmount - betAmountFee;
            uint256 profitPayout = profit - profitFee;
            // Transfer the bet amount from the contract
            if (isGasToken) {
                if (!user.send(betAmountPayout)) {
                    emit BetAmountTransferFail(
                        bet.id,
                        betAmountPayout,
                        "Gas token send failed"
                    );
                }
            } else {
                try
                    IERC20(token).transfer(user, betAmountPayout)
                {} catch Error(string memory reason) {
                    emit BetAmountTransferFail(bet.id, betAmountPayout, reason);
                }
                try
                    IERC20(token).transfer(address(bank), betAmountFee)
                {} catch Error(string memory reason) {
                    emit BetAmountFeeTransferFail(bet.id, betAmountFee, reason);
                }
            }

            // Transfer the payout from the bank, transfer the bet amount fee to the bank, and account fees.
            try
                bank.payout{value: isGasToken ? betAmountFee : 0}(
                    user,
                    token,
                    profitPayout,
                    fee
                )
            {} catch Error(string memory reason) {
                emit BetProfitTransferFail(bet.id, profitPayout, reason);
            }
        } else {
            payout = 0;
            if (!isGasToken) {
                try
                    IERC20(token).transfer(address(bank), betAmount)
                {} catch Error(string memory reason) {
                    emit BankTransferFail(bet.id, betAmount, reason);
                }
            }
            try
                bank.cashIn{value: isGasToken ? betAmount : 0}(token, betAmount)
            {} catch Error(string memory reason) {
                emit BankCashInFail(bet.id, betAmount, reason);
            }
        }

        bet.payout = payout;
        return payout;
    }

    /// @param user Address of the gamer.
    /// @param dataLength The amount of bets to return.
    /// @return A list of Bet.
    function _getLastUserBets(address user, uint256 dataLength)
        internal
        view
        returns (Bet[] memory)
    {
        uint256[] memory userBetsIds = _userBets[user];
        uint256 betsLength = userBetsIds.length;

        if (betsLength < dataLength) {
            dataLength = betsLength;
        }

        Bet[] memory userBets = new Bet[](dataLength);
        if (dataLength != 0) {
            uint256 userBetsIndex;
            for (uint256 i = betsLength; i > betsLength - dataLength; i--) {
                userBets[userBetsIndex] = bets[userBetsIds[i - 1]];
                userBetsIndex++;
            }
        }

        return userBets;
    }

    /// @param token Address of the token.
    /// @param houseEdge House edge rate.
    /// @dev The house edge rate couldn't exceed 4%.
    function setHouseEdge(address token, uint16 houseEdge) external onlyOwner {
        if (houseEdge > 400) {
            revert ExcessiveHouseEdge();
        }
        tokens[token].houseEdge = houseEdge;
        emit SetHouseEdge(token, houseEdge);
    }

    function pause() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    /// @param requestConfirmations How many confirmations the Chainlink node should wait before responding.
    /// @param keyHash Hash of the public key used to verify the VRF proof.
    function setChainlinkConfig(uint16 requestConfirmations, bytes32 keyHash)
        external
        onlyOwner
    {
        _chainlinkConfig.requestConfirmations = requestConfirmations;
        _chainlinkConfig.keyHash = keyHash;
        emit SetChainlinkConfig(requestConfirmations, keyHash);
    }

    /// @param callbackGasLimit How much gas is needed in the Chainlink VRF callback.
    function setVRFCallbackGasLimit(address token, uint32 callbackGasLimit)
        external
        onlyOwner
    {
        tokens[token].VRFCallbackGasLimit = callbackGasLimit;
        emit SetVRFCallbackGasLimit(token, callbackGasLimit);
    }

    /// @param token Address of the token.
    function withdrawTokensVRFFees(address token) external {
        uint256 tokenChainlinkFees = tokens[token].VRFFees;
        if (tokenChainlinkFees != 0) {
            delete tokens[token].VRFFees;
            payable(bank.getTokenOwner(token)).transfer(tokenChainlinkFees);
            emit DistributeTokenVRFFees(token, tokenChainlinkFees);
        }
    }

    /// @param id The Bet ID.
    function refundBet(uint256 id) external nonReentrant {
        Bet storage bet = bets[id];
        if (bet.resolved == true) {
            revert NotPendingBet();
        } else if (block.number < bet.blockNumber + 30) {
            revert NotFulfilled();
        }

        Token storage token = tokens[bet.token];
        token.pendingCount--;

        bet.resolved = true;
        bet.payout = bet.amount;

        if (bet.token == address(0)) {
            payable(bet.user).transfer(bet.amount);
        } else {
            IERC20(bet.token).safeTransfer(bet.user, bet.amount);
        }
        emit BetRefunded(id, bet.user, bet.amount);

        uint256 chainlinkVRFCost = bet.vrfCost;
        if (
            token.VRFFees >= chainlinkVRFCost &&
            address(this).balance >= chainlinkVRFCost
        ) {
            token.VRFFees -= chainlinkVRFCost;
            payable(bet.user).transfer(chainlinkVRFCost);
        } else {
            emit BetCostRefundFail(id, bet.user, chainlinkVRFCost);
        }
    }

    /// @notice Returns whether the token has pending bets.
    /// @return Whether the token has pending bets.
    function hasPendingBets(address token) external view returns (bool) {
        return tokens[token].pendingCount != 0;
    }

    /// @param _bank Address of the Bank contract.
    function setBank(IBank _bank) public onlyOwner {
        if (address(_bank) == address(0)) {
            revert InvalidAddress();
        }
        bank = _bank;
        emit SetBank(address(_bank));
    }

    /// @notice Returns the amount of ETH that should be passed to the wager transaction
    /// to cover Chainlink VRF fee.
    /// @return The bet resolution cost amount.
    function getChainlinkVRFCost(address token) public view returns (uint256) {
        (, int256 weiPerUnitLink, , , ) = _LINK_ETH_feed.latestRoundData();
        if (weiPerUnitLink <= 0) {
            revert InvalidLinkWeiPrice(weiPerUnitLink);
        }
        // Get Chainlink VRF v2 fee amount.
        (
            uint32 fulfillmentFlatFeeLinkPPMTier1,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = _chainlinkConfig.chainlinkCoordinator.getFeeConfig();
        // 115000 gas is the average Verification gas of Chainlink VRF.
        return
            (tx.gasprice * (115000 + tokens[token].VRFCallbackGasLimit)) +
            ((1e12 *
                uint256(fulfillmentFlatFeeLinkPPMTier1) *
                uint256(weiPerUnitLink)) / 1e18);
        // fulfillmentFlatFeeLinkPPMTier1,
    }

    function testVRFCost(address token) public view returns (uint256[] memory) {
        (, int256 weiPerUnitLink, , , ) = _LINK_ETH_feed.latestRoundData();
        if (weiPerUnitLink <= 0) {
            revert InvalidLinkWeiPrice(weiPerUnitLink);
        }
        // Get Chainlink VRF v2 fee amount.
        (
            uint32 fulfillmentFlatFeeLinkPPMTier1,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = _chainlinkConfig.chainlinkCoordinator.getFeeConfig();

        uint256 finalCost = (tx.gasprice *
            (115000 + tokens[token].VRFCallbackGasLimit)) +
            ((1e12 *
                uint256(fulfillmentFlatFeeLinkPPMTier1) *
                uint256(weiPerUnitLink)) / 1e18);

        uint256[] memory numbers = new uint256[](4);
        numbers[0] = uint256(fulfillmentFlatFeeLinkPPMTier1);
        numbers[1] = uint256(weiPerUnitLink);
        numbers[2] = (tx.gasprice *
            (115000 + tokens[token].VRFCallbackGasLimit));
        numbers[3] = finalCost;
        return numbers;
    }
}

// wager (roulette)
// => new_bet (game)
// => request_random_words (VRFCoordinatorV2Interface)
// => random (roulette VRFConsumerBaseV2) => resolve(game)

//  setBank(IBank _bank) public onlyOwner

//  pause() external onlyOwner

//  _getFees(address token, uint256 amount) private returns (uint256)

//  _newBet(address tokenAddress, uint256 tokenAmount, uint256 multiplier) internal whenNotPaused nonReentrant returns (Bet memory)

//  _resolveBet(Bet storage bet, bool wins, uint256 payout) internal returns (uint256)

//  setHouseEdge(address token, uint16 houseEdge) external onlyOwner 350

//  setChainlinkConfig(uint16 requestConfirmations, bytes32 keyHash) external onlyOwner 3,

//  setVRFCallbackGasLimit(address token, uint32 callbackGasLimit) external onlyOwner 100000

//  withdrawTokensVRFFees(address token) external

//  refundBet(uint256 id) external nonReentrant

//  hasPendingBets(address token) external view returns (bool)

//  getChainlinkVRFCost(address token) public view returns (uint256)

//  _getLastUserBets(address user, uint256 dataLength) internal returns (Bet[] memory)
