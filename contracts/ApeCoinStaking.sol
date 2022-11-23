//SPDX-License-Identifier: MIT

/*
ApeStake Smart Contract Disclaimer

The ApeStake smart contract (the “Smart Contract”) was developed at the direction of the ApeCoin DAO community pursuant
to a grant by the Ape Foundation.  The grant instructs the development of the Smart Contract and the developer’s user
interface to enable a non-exclusive, user friendly means of access to the rewards program offered to the APE community
by the Ape Foundation pursuant to the specifications set forth in AIPs 21/22. The Smart Contract is made up of free,
public, open-source or source-available software deployed on the Ethereum Blockchain.

Use Disclaimer.
Your use of the Smart Contract involves various risks, including, but not limited to, losses while digital
assets are being supplied and/or removed from the Smart Contract, losses due to the volatility of token price,
risks in connection with your personal wallet access, system failures, opportunity loss while participating in the
Smart Contract, loss of tokens in connection with non-fungible token transfers, risk of cyber attack and/or security
breach, risk of legal uncertainty and/or changes in legal environment, and additional risks which may be based upon
utilization of any third party other than the Smart Contract developer who provides you with access to the Smart
Contract. Before using the Smart Contract, you should review the relevant documentation to make sure you understand
how the Smart Contract works. Additionally, because you may be able to access the Smart Contract through other web or
mobile interfaces than the Smart Contract developer’s user interface provided pursuant to the Ape Foundation grant,
you are responsible for doing your own diligence on those interfaces to understand the fees and risks they present.

THE SMART CONTRACT IS PROVIDED "AS IS", AT YOUR OWN RISK, AND WITHOUT WARRANTIES OF ANY KIND.
The developer was contracted by APE Foundation to develop the initial code to implement AIP 21/22.
The developer does not own or control the staking rewards program, which is run on the Smart Contracts deployed on
the Ethereum blockchain.  Upgrades and modifications will be managed in a community-driven way by holders of the APE
governance token and may be undertaken and/or implemented with no involvement of the developer.

No liability.
No developer or entity involved in creating the Smart Contract or “platform as a service” will be liable for any
claims or damages whatsoever associated with your use, inability to use, or your interaction with the Smart Contract
or the developer’s user interface provided pursuant to the Ape Foundation grant, including any direct, indirect,
incidental, special, exemplary, punitive or consequential damages, or loss of profits, cryptocurrencies, tokens,
or anything else of value.

Access to Third Parties.
Any party who uses or provides access to the Smart Contract to third parties must (a) not provide such access in
violation of any applicable law or regulation, (b) inform such third parties of any and all risks, and (c) is solely
responsible to such third parties for any and all liability, claims or damages relating to such party’s provision of
access to the Smart Contract.
*/
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/** OPTIMIZE:
   SafeERC20 is not needed in the case of apecoin staking, since it is meant for
   when there is an interaction with unknown tokens which might not adhere to ERC20 standard
   but since APE$ as displayed on ETHERSCAN adhere to it and returns true on successful transfer or transfreFrom
   or reverts with a valid message, then it's safe to transfer and transferFrom directly without extra check for return data
 */
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/**
 * OPTIMIZE: 
    all require functions turned into error statments
    since when a transaction reverts, 
    it consumes far less gas compared to require statments

    when there is multiple boolean checks, 
    De Morgan Theorem is used
    ~(A AND B) <==> (~A OR ~B) 
    ~(A OR B) <==> (~A AND ~B)
 */
error DepositMoreThanOneAPE();
error InvalidPoolId();
error StartMustBeMoreThanEnd();
error StartNotWholeHour();
error EndNotWholeHour();
error StartMustEqualLastEnd();
error CallerNotOwner();
error TokenNotOwnedOrPaired();
error BAKCNotOwnedOrPaired();
error BAKCAlreadyPaired();
error ExceededCapAmount();
error NotOwnerOfMain();
error NotOwnerOfBAKC();
error ProvidedTokensNotPaired();
error ExceededStakedAmount();
error CallerNotTokenOwnerInPair();
error SplitPairCantPartiallyWithdraw();

/**
 * @title ApeCoin Staking Contract
 * @notice Stake ApeCoin across four different pools that release hourly rewards
 * @author HorizenLabs
 */
contract ApeCoinStaking is Ownable {

    using SafeCast for uint256;
    using SafeCast for int256;

    /// @notice State for ApeCoin, BAYC, MAYC, and Pair Pools
    /** OPTIMIZE
        following struct optimizations are made to make the most out of storage slots while adhereing to the requirements
    */
    /** OPTIMIZE
     * 'lastRewardedTimestampHour'
            8925460 years is left for it to max out on 48 bits

            we have: block.timestamp + 3 years = 1.77e9 << 2**48-1 = 2.8e14
            RESULT: safe to use 96 bits
     *  'lastRewardsRangeIndex'
            since each index refers to the position of TimeRanges which has a period of 3 months
            and in total we have 3 year staking, so in total 3 * 4 * 3 = 36

            we have 3 * 4 * 3 = 36 << 2**16 - 1
            RESULT: safe to use 16 bits 
     * 'stakedAmount'
            the extreme value that can be staked is the total supply for extra safety:
             which is 1e9 * 1e18
    
            we have 1e9 * 1e18 = 1e27 << 2**96-1 = 7.9e28
            RESULT: safe to use 96 bits
     * 'accumulatedRewardsPerShare'
            the accumulation of the calculated:
              +=  (rewards * APE_COIN_PRECISION) / pool.stakedAmount
            and the least pool.stakedAmount can reach to is 1 APE$ which is 1e18
            and the max amount for rewards is the total possible rewards 175 * 1e6 * 1e18
            substitute within the forumla results in total possible rewards 
            since APE_COIN_PRECISION cancels out MAX of pool.stakedAmount

            we have 175 * 1e6 * 1e18 = 1.75e+26 << 2**96 - 1 = 7.9e28 
            RESULT: safe to use 96 bits
     */
    struct Pool {
        uint48 lastRewardedTimestampHour;
        uint16 lastRewardsRangeIndex;
        uint96 stakedAmount;
        uint96 accumulatedRewardsPerShare;
        TimeRange[] timeRanges;
    }

    /// @notice Pool rules valid for a given duration of time.
    /// @dev All TimeRange timestamp values must represent whole hours

    /** OPTIMIZE
     * 'startTimestampHour' and 'endTimestampHour' can perfectly fit in 48 bits for each
     * 'rewardsPerHour' 
       highest possible value is 16_486_750e18 * 3600 / 91 days ~= 7.55e21 << 2**80 - 1 ~= 1.2e24

       RESULT: safe to use 80 bits
     * 'capPerPosition'
        highest cap amount is 10094 APE$
        since 10094e18 << 2**80 - 1 ~= 1.2e24

        RESULT: safe to use 80 bits
     */
    struct TimeRange {
        uint48 startTimestampHour;
        uint48 endTimestampHour;
        uint80 rewardsPerHour;
        uint80 capPerPosition;
    }

    /// @dev Per address amount and reward tracking
    struct Position {
        /**
         * 'stakedAmount'
            the highest that can be staked is the capped amount which is 10094e18
    
            we have 10094e18 = 1.0094e22 << 2**80-1 = 1.2e24
            RESULT: safe to use 80 bits
         * 'rewardsDebt'
            = (position deposited / withdraw amount) * pool.accumulatedRewardsPerShare
            since the capped amount is 10094e18
            and accumulatedRewardsPerShare as we have deomnstrated previously would have
            total rewards as the max value 175 * 1e6 * 1e18

            we have 10094e18 * 175 * 1e6 * 1e18 = 1.77e+48 << 2**176-1 = 9.57e+52
            RESULT: safe to use 176 bits
         */
        // 1.75e+26 * 10094e18
        uint80 stakedAmount;
        int176 rewardsDebt;
        // uint256 stakedAmount;
        // int256 rewardsDebt;
    }

    /** OPTIMIZE
     * 'tokenId':
        it has very low values in the 10s of thousands
        
        RESULT: safe to use 32 btis.
     * 'amount':
            highest amount is the highest cap amount which is 10094 APE$
            since 10094e18 << 2**224 - 1 ~= 2.69e67
        
        RESULT: safe to use 224 btis.
     */
    /// @dev Struct for depositing and withdrawing from the BAYC and MAYC NFT pools
    struct SingleNft {
        uint32 tokenId;
        uint224 amount;
    }

    /// @dev Struct for depositing and withdrawing from the BAKC (Pair) pool
    /** OPTIMIZE
     * 'mainTokenId' and 'bakcTokenId':
        it has very low values in the 10s of thousands
        
        RESULT: safe to use 32 btis.
     * 'amount':
            highest amount is the highest cap amount which is 10094 APE$
            since 10094e18 << 2**192 - 1 ~= 6.27e57
    
        RESULT: safe to use 192 btis.
     */
    struct PairNftWithAmount {
        uint32 mainTokenId;
        uint32 bakcTokenId;
        uint192 amount;
    }

    /// @dev Struct for claiming from an NFT pool
    /** OPTIMIZE
     * 'mainTokenId' and 'bakcTokenId':
        it has very low values in the 10s of thousands
        
        RESULT: safe to use 128 btis.
     */
    struct PairNft {
        uint128 mainTokenId;
        uint128 bakcTokenId;
    }

    /// @dev NFT paired status.  Can be used bi-directionally (BAYC/MAYC -> BAKC) or (BAKC -> BAYC/MAYC)
    /** OPTIMIZE
     * 'tokenId':
        it has very low values in the 10s of thousands
        RESULT: safe to use 248 btis.
     * 'isPaired'
        would fit in the remaining 8 bits within storage slot
     */
    struct PairingStatus {
        uint248 tokenId;
        bool isPaired;
    }

    /// @dev Convenience struct for front-end applications
    struct PoolUI {
        uint256 poolId;
        uint256 stakedAmount;
        TimeRange currentTimeRange;
    }

    // @dev UI focused payload
    struct DashboardStake {
        uint256 poolId;
        uint256 tokenId;
        uint256 deposited;
        uint256 unclaimed;
        uint256 rewards24hr;
        DashboardPair pair;
    }
    /// @dev Sub struct for DashboardStake
    struct DashboardPair {
        uint256 mainTokenId;
        uint256 mainTypePoolId;
    }
    /// @dev Placeholder for pair status, used by ApeCoin Pool
    DashboardPair private NULL_PAIR = DashboardPair(0, 0);

    /// @notice Internal ApeCoin amount for distributing staking reward claims
    IERC20 private immutable apeCoin;
    uint256 private constant APE_COIN_PRECISION = 1e18;
    uint256 private constant MIN_DEPOSIT = 1 * APE_COIN_PRECISION;
    uint256 private constant SECONDS_PER_HOUR = 3600;
    uint256 private constant SECONDS_PER_MINUTE = 60;

    uint256 constant APECOIN_POOL_ID = 0;
    uint256 constant BAYC_POOL_ID = 1;
    uint256 constant MAYC_POOL_ID = 2;
    uint256 constant BAKC_POOL_ID = 3;
    Pool[4] private pools;

    /// @dev user => position
    mapping (address => Position) private addressPosition;
    /// @dev NFT contract mapping per pool
    mapping(uint256 => ERC721Enumerable) private nftContracts;
    /// @dev poolId => tokenId => nft position
    mapping(uint256 => mapping(uint256 => Position)) private nftPosition;
    /// @dev main type pool ID: 1: BAYC 2: MAYC => main token ID => bakc token ID
    mapping(uint256 => mapping(uint256 => PairingStatus)) private mainToBakc;
    /// @dev bakc Token ID => main type pool ID: 1: BAYC 2: MAYC => main token ID
    mapping(uint256 => mapping(uint256 => PairingStatus)) private bakcToMain;

    /** Custom Events */
    event UpdatePool(
        uint256 indexed poolId,
        uint256 lastRewardedBlock,
        uint256 stakedAmount,
        uint256 accumulatedRewardsPerShare
    );
    event Deposit(
        address indexed user,
        uint256 amount,
        address recipient
    );
    event DepositNft(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 tokenId
    );
    event DepositPairNft(
        address indexed user,
        uint256 amount,
        uint256 mainTypePoolId,
        uint256 mainTokenId,
        uint256 bakcTokenId
    );
    event Withdraw(
        address indexed user,
        uint256 amount,
        address recipient
    );
    event WithdrawNft(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        address recipient,
        uint256 tokenId
    );
    event WithdrawPairNft(
        address indexed user,
        uint256 amount,
        uint256 mainTypePoolId,
        uint256 mainTokenId,
        uint256 bakcTokenId
    );
    event ClaimRewards(
        address indexed user,
        uint256 amount,
        address recipient
    );
    event ClaimRewardsNft(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 tokenId
    );
    event ClaimRewardsPairNft(
        address indexed user,
        uint256 amount,
        uint256 mainTypePoolId,
        uint256 mainTokenId,
        uint256 bakcTokenId
    );

    /**
     * @notice Construct a new ApeCoinStaking instance
     * @param _apeCoinContractAddress The ApeCoin ERC20 contract address
     * @param _baycContractAddress The BAYC NFT contract address
     * @param _maycContractAddress The MAYC NFT contract address
     * @param _bakcContractAddress The BAKC NFT contract address
     */
    constructor(
        address _apeCoinContractAddress,
        address _baycContractAddress,
        address _maycContractAddress,
        address _bakcContractAddress
    ) {
        apeCoin = IERC20(_apeCoinContractAddress);
        nftContracts[BAYC_POOL_ID] = ERC721Enumerable(_baycContractAddress);
        nftContracts[MAYC_POOL_ID] = ERC721Enumerable(_maycContractAddress);
        nftContracts[BAKC_POOL_ID] = ERC721Enumerable(_bakcContractAddress);
    }

    // Deposit/Commit Methods

    /**
     * @notice Deposit ApeCoin to the ApeCoin Pool
     * @param _amount Amount in ApeCoin
     * @param _recipient Address the deposit it stored to
     * @dev ApeCoin deposit must be >= 1 ApeCoin
     */
    function depositApeCoin(uint256 _amount, address _recipient) public {
        if (_amount < MIN_DEPOSIT) revert DepositMoreThanOneAPE();
        updatePool(APECOIN_POOL_ID);

        Position storage position = addressPosition[_recipient];
        _deposit(APECOIN_POOL_ID, position, _amount);
        /* 
         * safeTransferFrom is an overkill, after checking APECOIN ERC20 contract on etherscan,
         * you would notice that it adhere to ERC20 token standard and returns actually true on successful transferFrom
         * or reverts.
         */
        apeCoin.transferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount, _recipient);
    }

    /**
     * @notice Deposit ApeCoin to the ApeCoin Pool
     * @param _amount Amount in ApeCoin
     * @dev Deposit on behalf of msg.sender. ApeCoin deposit must be >= 1 ApeCoin
     */
    function depositSelfApeCoin(uint256 _amount) external {
        depositApeCoin(_amount, msg.sender);
    }

    /**
     * @notice Deposit ApeCoin to the BAYC Pool
     * @param _nfts Array of SingleNft structs
     * @dev Commits 1 or more BAYC NFTs, each with an ApeCoin amount to the BAYC pool.\
     * Each BAYC committed must attach an ApeCoin amount >= 1 ApeCoin and <= the BAYC pool cap amount.
     */
    function depositBAYC(SingleNft[] calldata _nfts) external {
        _depositNft(BAYC_POOL_ID, _nfts);
    }

    /**
     * @notice Deposit ApeCoin to the MAYC Pool
     * @param _nfts Array of SingleNft structs
     * @dev Commits 1 or more MAYC NFTs, each with an ApeCoin amount to the MAYC pool.\
     * Each MAYC committed must attach an ApeCoin amount >= 1 ApeCoin and <= the MAYC pool cap amount.
     */
    function depositMAYC(SingleNft[] calldata _nfts) external {
        _depositNft(MAYC_POOL_ID, _nfts);
    }

    /**
     * @notice Deposit ApeCoin to the Pair Pool, where Pair = (BAYC + BAKC) or (MAYC + BAKC)
     * @param _baycPairs Array of PairNftWithAmount structs
     * @param _maycPairs Array of PairNftWithAmount structs
     * @dev Commits 1 or more Pairs, each with an ApeCoin amount to the Pair pool.\
     * Each BAKC committed must attach an ApeCoin amount >= 1 ApeCoin and <= the Pair pool cap amount.\
     * Example 1: BAYC + BAKC + 1 ApeCoin:  [[0, 0, "1000000000000000000"],[]]\
     * Example 2: MAYC + BAKC + 1 ApeCoin:  [[], [0, 0, "1000000000000000000"]]\
     * Example 3: (BAYC + BAKC + 1 ApeCoin) and (MAYC + BAKC + 1 ApeCoin): [[0, 0, "1000000000000000000"], [0, 1, "1000000000000000000"]]
     */
    function depositBAKC(PairNftWithAmount[] calldata _baycPairs, PairNftWithAmount[] calldata _maycPairs) external {
        updatePool(BAKC_POOL_ID);
        _depositPairNft(BAYC_POOL_ID, _baycPairs);
        _depositPairNft(MAYC_POOL_ID, _maycPairs);
    }

    // Claim Rewards Methods

    /**
     * @notice Claim rewards for msg.sender and send to recipient
     * @param _recipient Address to send claim reward to
     */
    function claimApeCoin(address _recipient) public {
        updatePool(APECOIN_POOL_ID);

        Position storage position = addressPosition[msg.sender];
        uint256 rewardsToBeClaimed = _claim(APECOIN_POOL_ID, position, _recipient);

        emit ClaimRewards(msg.sender, rewardsToBeClaimed, _recipient);
    }

    /// @notice Claim and send rewards
    function claimSelfApeCoin() external {
        claimApeCoin(msg.sender);
    }

    /**
     * @notice Claim rewards for array of BAYC NFTs and send to recipient
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimBAYC(uint256[] calldata _nfts, address _recipient) external {
        _claimNft(BAYC_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Claim rewards for array of BAYC NFTs
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     */
    function claimSelfBAYC(uint256[] calldata _nfts) external {
        _claimNft(BAYC_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Claim rewards for array of MAYC NFTs and send to recipient
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimMAYC(uint256[] calldata _nfts, address _recipient) external {
        _claimNft(MAYC_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Claim rewards for array of MAYC NFTs
     * @param _nfts Array of NFTs owned and committed by the msg.sender
     */
    function claimSelfMAYC(uint256[] calldata _nfts) external {
        _claimNft(MAYC_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Claim rewards for array of Paired NFTs and send to recipient
     * @param _baycPairs Array of Paired BAYC NFTs owned and committed by the msg.sender
     * @param _maycPairs Array of Paired MAYC NFTs owned and committed by the msg.sender
     * @param _recipient Address to send claim reward to
     */
    function claimBAKC(PairNft[] calldata _baycPairs, PairNft[] calldata _maycPairs, address _recipient) public {
        updatePool(BAKC_POOL_ID);
        _claimPairNft(BAYC_POOL_ID, _baycPairs, _recipient);
        _claimPairNft(MAYC_POOL_ID, _maycPairs, _recipient);
    }

    /**
     * @notice Claim rewards for array of Paired NFTs
     * @param _baycPairs Array of Paired BAYC NFTs owned and committed by the msg.sender
     * @param _maycPairs Array of Paired MAYC NFTs owned and committed by the msg.sender
     */
    function claimSelfBAKC(PairNft[] calldata _baycPairs, PairNft[] calldata _maycPairs) external {
        claimBAKC(_baycPairs, _maycPairs, msg.sender);
    }

    // Uncommit/Withdraw Methods

    /**
     * @notice Withdraw staked ApeCoin from the ApeCoin pool.  Performs an automatic claim as part of the withdraw process.
     * @param _amount Amount of ApeCoin
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawApeCoin(uint256 _amount, address _recipient) public {
        updatePool(APECOIN_POOL_ID);

        Position storage position = addressPosition[msg.sender];
        if (_amount == position.stakedAmount) {
            uint256 rewardsToBeClaimed = _claim(APECOIN_POOL_ID, position, _recipient);
            emit ClaimRewards(msg.sender, rewardsToBeClaimed, _recipient);
        }
        _withdraw(APECOIN_POOL_ID, position, _amount);
        // SafeTransfer is an overkill, after checking APECOIN ERC20 contract on etherscan,
        // you would notice that it adhere to ERC20 token standard and returns actually true on successful transfer
        // or reverts.
        apeCoin.transfer(_recipient, _amount);
        emit Withdraw(msg.sender, _amount, _recipient);
    }

    /**
     * @notice Withdraw staked ApeCoin from the ApeCoin pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _amount Amount of ApeCoin
     */
    function withdrawSelfApeCoin(uint256 _amount) external {
        withdrawApeCoin(_amount, msg.sender);
    }

    /**
     * @notice Withdraw staked ApeCoin from the BAYC pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of BAYC NFT's with staked amounts
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawBAYC(SingleNft[] calldata _nfts, address _recipient) external {
        _withdrawNft(BAYC_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Withdraw staked ApeCoin from the BAYC pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of BAYC NFT's with staked amounts
     */
    function withdrawSelfBAYC(SingleNft[] calldata _nfts) external {
        _withdrawNft(BAYC_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Withdraw staked ApeCoin from the MAYC pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of MAYC NFT's with staked amounts
     * @param _recipient Address to send withdraw amount and claim to
     */
    function withdrawMAYC(SingleNft[] calldata _nfts, address _recipient) external {
        _withdrawNft(MAYC_POOL_ID, _nfts, _recipient);
    }

    /**
     * @notice Withdraw staked ApeCoin from the MAYC pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _nfts Array of MAYC NFT's with staked amounts
     */
    function withdrawSelfMAYC(SingleNft[] calldata _nfts) external {
        _withdrawNft(MAYC_POOL_ID, _nfts, msg.sender);
    }

    /**
     * @notice Withdraw staked ApeCoin from the Pair pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param _baycPairs Array of Paired BAYC NFT's with staked amounts
     * @param _maycPairs Array of Paired MAYC NFT's with staked amounts
     * @dev if pairs have split ownership and BAKC is attempting a withdraw, the withdraw must be for the total staked amount
     */
    function withdrawBAKC(PairNftWithAmount[] calldata _baycPairs, PairNftWithAmount[] calldata _maycPairs) external {
        updatePool(BAKC_POOL_ID);
        _withdrawPairNft(BAYC_POOL_ID, _baycPairs);
        _withdrawPairNft(MAYC_POOL_ID, _maycPairs);
    }

    // Time Range Methods

    /**
     * @notice Add single time range with a given rewards per hour for a given pool
     * @dev In practice one Time Range will represent one quarter (defined by `_startTimestamp`and `_endTimeStamp` as whole hours)
     * where the rewards per hour is constant for a given pool.
     * @param _poolId Available pool values 0-3
     * @param _amount Total amount of ApeCoin to be distributed over the range
     * @param _startTimestamp Whole hour timestamp representation
     * @param _endTimeStamp Whole hour timestamp representation
     * @param _capPerPosition Per position cap amount determined by poolId
     */
    function addTimeRange(
        uint256 _poolId,
        uint256 _amount,
        uint256 _startTimestamp,
        uint256 _endTimeStamp,
        uint256 _capPerPosition) external onlyOwner
    {
        if (_poolId > BAKC_POOL_ID) revert InvalidPoolId();
        if (_startTimestamp >= _endTimeStamp) revert StartMustBeMoreThanEnd();
        if (getMinute(_startTimestamp) > 0 || getSecond(_startTimestamp) > 0)
            revert StartNotWholeHour();
        if (getMinute(_endTimeStamp) > 0 || getSecond(_endTimeStamp) > 0)
            revert EndNotWholeHour();

        Pool storage pool = pools[_poolId];
        uint256 len = pool.timeRanges.length;
        if (len > 0)
            if (_startTimestamp != pool.timeRanges[len - 1].endTimestampHour)
                revert StartMustEqualLastEnd();

        uint256 hoursInSeconds = _endTimeStamp - _startTimestamp;
        uint256 rewardsPerHour = _amount * SECONDS_PER_HOUR / hoursInSeconds;

        TimeRange memory next = TimeRange(uint48(_startTimestamp), uint48(_endTimeStamp), uint80(rewardsPerHour), uint80(_capPerPosition));
        pool.timeRanges.push(next);
    }

    /**
     * @notice Removes the last Time Range for a given pool.
     * @param _poolId Available pool values 0-3
     */
    function removeLastTimeRange(uint256 _poolId) external onlyOwner {
        Pool storage pool = pools[_poolId];
        pool.timeRanges.pop();
    }

    /**
     * @notice Lookup method for a TimeRange struct
     * @return TimeRange A Pool's timeRanges struct by index.
     * @param _poolId Available pool values 0-3
     * @param _index Target index in a Pool's timeRanges array
     */
    function getTimeRangeBy(uint256 _poolId, uint256 _index) public view returns (TimeRange memory) {
        Pool memory pool = pools[_poolId];
        return pool.timeRanges[_index];
    }

    // Pool Methods

    /**
     * @notice Lookup available rewards for a pool over a given time range
     * @return uint256 The amount of ApeCoin rewards to be distributed by pool for a given time range
     * @return uint256 The amount of time ranges
     * @param _poolId Available pool values 0-3
     * @param _from Whole hour timestamp representation
     * @param _to Whole hour timestamp representation
     */
    function rewardsBy(uint256 _poolId, uint256 _from, uint256 _to) public view returns (uint256, uint256) {
        Pool memory pool = pools[_poolId];
        uint256 currentIndex = pool.lastRewardsRangeIndex;
        if(_to < pool.timeRanges[0].startTimestampHour) return (0, currentIndex);

        while(_from > pool.timeRanges[currentIndex].endTimestampHour && _to > pool.timeRanges[currentIndex].endTimestampHour) {
            unchecked {
                ++currentIndex;
            }
        }

        uint256 rewards;
        TimeRange memory current;
        uint256 startTimestampHour;
        uint256 endTimestampHour;
        uint256 len = pool.timeRanges.length;
        for(uint256 i = currentIndex; i < len;) {
            current = pool.timeRanges[i];

            startTimestampHour = _from <= current.startTimestampHour ? current.startTimestampHour : _from;
            endTimestampHour = _to <= current.endTimestampHour ? _to : current.endTimestampHour;
            rewards = rewards + (endTimestampHour - startTimestampHour) * current.rewardsPerHour / SECONDS_PER_HOUR;

            if(_to <= endTimestampHour) {
                return (rewards, i);
            }
            unchecked {
                ++i;
            }
        }

        return (rewards, len - 1);
    }

    /**
     * @notice Updates reward variables `lastRewardedTimestampHour`, `accumulatedRewardsPerShare` and `lastRewardsRangeIndex`
     * for a given pool.
     * @param _poolId Available pool values 0-3
     */
    function updatePool(uint256 _poolId) public {
        Pool storage pool = pools[_poolId];

        if (block.timestamp < pool.timeRanges[0].startTimestampHour) return;
        if (block.timestamp <= pool.lastRewardedTimestampHour + SECONDS_PER_HOUR) return;

        uint48 lastTimestampHour = pool.timeRanges[pool.timeRanges.length-1].endTimestampHour;
        uint48 previousTimestampHour = uint48(getPreviousTimestampHour());

        if (pool.stakedAmount == 0) {
            pool.lastRewardedTimestampHour = previousTimestampHour > lastTimestampHour ? lastTimestampHour : previousTimestampHour;
            return;
        }

        (uint256 rewards, uint256 index) = rewardsBy(_poolId, pool.lastRewardedTimestampHour, previousTimestampHour);
        if (pool.lastRewardsRangeIndex != index) {
            pool.lastRewardsRangeIndex = uint16(index);
        }
        pool.accumulatedRewardsPerShare = uint96(pool.accumulatedRewardsPerShare + (rewards * APE_COIN_PRECISION) / pool.stakedAmount);
        pool.lastRewardedTimestampHour = previousTimestampHour > lastTimestampHour ? lastTimestampHour : previousTimestampHour;

        emit UpdatePool(_poolId, pool.lastRewardedTimestampHour, pool.stakedAmount, pool.accumulatedRewardsPerShare);
    }

    // Read Methods

    function getCurrentTimeRangeIndex(Pool memory pool) private view returns (uint256) {
        uint256 current = pool.lastRewardsRangeIndex;

        if (block.timestamp < pool.timeRanges[current].startTimestampHour) return current;
        for(current = pool.lastRewardsRangeIndex; current < pool.timeRanges.length; ++current) {
            TimeRange memory currentTimeRange = pool.timeRanges[current];
            if (currentTimeRange.startTimestampHour <= block.timestamp && block.timestamp <= currentTimeRange.endTimestampHour) return current;
        }
        revert("distribution ended");
    }

    /**
     * @notice Fetches a PoolUI struct (poolId, stakedAmount, currentTimeRange) for each reward pool
     * @return PoolUI for ApeCoin.
     * @return PoolUI for BAYC.
     * @return PoolUI for MAYC.
     * @return PoolUI for BAKC.
     */
    function getPoolsUI() public view returns (PoolUI memory, PoolUI memory, PoolUI memory, PoolUI memory) {
        Pool memory apeCoinPool = pools[0];
        Pool memory baycPool = pools[1];
        Pool memory maycPool = pools[2];
        Pool memory bakcPool = pools[3];
        uint256 current = getCurrentTimeRangeIndex(apeCoinPool);
        return (PoolUI(0,apeCoinPool.stakedAmount, apeCoinPool.timeRanges[current]),
                PoolUI(1,baycPool.stakedAmount, baycPool.timeRanges[current]),
                PoolUI(2,maycPool.stakedAmount, maycPool.timeRanges[current]),
                PoolUI(3,bakcPool.stakedAmount, bakcPool.timeRanges[current]));
    }

    /**
     * @notice Fetches an address total staked amount, used by voting contract
     * @return amount uint256 staked amount for all pools.
     * @param _address An Ethereum address
     */
    function stakedTotal(address _address) external view returns (uint256) {
        uint256 total = addressPosition[_address].stakedAmount;

        total += _stakedTotal(BAYC_POOL_ID, _address);
        total += _stakedTotal(MAYC_POOL_ID, _address);
        total += _stakedTotalPair(_address);

        return total;
    }

    function _stakedTotal(uint256 _poolId, address _addr) private view returns (uint256) {
        uint256 total = 0;
        uint256 nftCount = nftContracts[_poolId].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 tokenId = nftContracts[_poolId].tokenOfOwnerByIndex(_addr, i);
            total += nftPosition[_poolId][tokenId].stakedAmount;
        }

        return total;
    }

    function _stakedTotalPair(address _addr) private view returns (uint256) {
        uint256 total = 0;

        uint256 nftCount = nftContracts[BAYC_POOL_ID].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 baycTokenId = nftContracts[BAYC_POOL_ID].tokenOfOwnerByIndex(_addr, i);
            if (mainToBakc[BAYC_POOL_ID][baycTokenId].isPaired) {
                uint256 bakcTokenId = mainToBakc[BAYC_POOL_ID][baycTokenId].tokenId;
                total += nftPosition[BAKC_POOL_ID][bakcTokenId].stakedAmount;
            }
        }

        nftCount = nftContracts[MAYC_POOL_ID].balanceOf(_addr);
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 maycTokenId = nftContracts[MAYC_POOL_ID].tokenOfOwnerByIndex(_addr, i);
            if (mainToBakc[MAYC_POOL_ID][maycTokenId].isPaired) {
                uint256 bakcTokenId = mainToBakc[MAYC_POOL_ID][maycTokenId].tokenId;
                total += nftPosition[BAKC_POOL_ID][bakcTokenId].stakedAmount;
            }
        }

        return total;
    }

    /**
     * @notice Fetches a DashboardStake = [poolId, tokenId, deposited, unclaimed, rewards24Hrs, paired] \
     * for each pool, for an Ethereum address
     * @return dashboardStakes An array of DashboardStake structs
     * @param _address An Ethereum address
     */
    function getAllStakes(address _address) public view returns (DashboardStake[] memory) {

        DashboardStake memory apeCoinStake = getApeCoinStake(_address);
        DashboardStake[] memory baycStakes = getBaycStakes(_address);
        DashboardStake[] memory maycStakes = getMaycStakes(_address);
        DashboardStake[] memory bakcStakes = getBakcStakes(_address);
        DashboardStake[] memory splitStakes = getSplitStakes(_address);

        uint256 count = (baycStakes.length + maycStakes.length + bakcStakes.length + splitStakes.length + 1);
        DashboardStake[] memory allStakes = new DashboardStake[](count);

        uint256 offset = 0;
        allStakes[offset] = apeCoinStake;
        ++offset;

        for(uint256 i = 0; i < baycStakes.length; ++i) {
            allStakes[offset] = baycStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < maycStakes.length; ++i) {
            allStakes[offset] = maycStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < bakcStakes.length; ++i) {
            allStakes[offset] = bakcStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < splitStakes.length; ++i) {
            allStakes[offset] = splitStakes[i];
            ++offset;
        }

        return allStakes;
    }

    /**
     * @notice Fetches a DashboardStake for the ApeCoin pool
     * @return dashboardStake A dashboardStake struct
     * @param _address An Ethereum address
     */
    function getApeCoinStake(address _address) public view returns (DashboardStake memory) {
        uint256 tokenId = 0;
        uint256 deposited = addressPosition[_address].stakedAmount;
        uint256 unclaimed = deposited > 0 ? this.pendingRewards(0, _address, tokenId) : 0;
        uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(0, _address, 0) : 0;

        return DashboardStake(APECOIN_POOL_ID, tokenId, deposited, unclaimed, rewards24Hrs, NULL_PAIR);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the BAYC pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getBaycStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, BAYC_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the MAYC pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getMaycStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, MAYC_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the BAKC pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getBakcStakes(address _address) public view returns (DashboardStake[] memory) {
        return _getStakes(_address, BAKC_POOL_ID);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the Pair Pool when ownership is split \
     * ie (BAYC/MAYC) and BAKC in pair pool have different owners.
     * @return dashboardStakes An array of DashboardStake structs
     * @param _address An Ethereum address
     */
    function getSplitStakes(address _address) public view returns (DashboardStake[] memory) {
        uint256 baycSplits = _getSplitStakeCount(nftContracts[BAYC_POOL_ID].balanceOf(_address), _address, BAYC_POOL_ID);
        uint256 maycSplits = _getSplitStakeCount(nftContracts[MAYC_POOL_ID].balanceOf(_address), _address, MAYC_POOL_ID);
        uint256 totalSplits = baycSplits + maycSplits;

        if(totalSplits == 0) {
            return new DashboardStake[](0);
        }

        DashboardStake[] memory baycSplitStakes = _getSplitStakes(baycSplits, _address, BAYC_POOL_ID);
        DashboardStake[] memory maycSplitStakes = _getSplitStakes(maycSplits, _address, MAYC_POOL_ID);

        DashboardStake[] memory splitStakes = new DashboardStake[](totalSplits);
        uint256 offset = 0;
        for(uint256 i = 0; i < baycSplitStakes.length; ++i) {
            splitStakes[offset] = baycSplitStakes[i];
            ++offset;
        }

        for(uint256 i = 0; i < maycSplitStakes.length; ++i) {
            splitStakes[offset] = maycSplitStakes[i];
            ++offset;
        }

        return splitStakes;
    }

    function _getSplitStakes(uint256 splits, address _address, uint256 _mainPoolId) private view returns (DashboardStake[] memory) {

        DashboardStake[] memory dashboardStakes = new DashboardStake[](splits);
        uint256 counter;

        for(uint256 i = 0; i < nftContracts[_mainPoolId].balanceOf(_address); ++i) {
            uint256 mainTokenId = nftContracts[_mainPoolId].tokenOfOwnerByIndex(_address, i);
            if(mainToBakc[_mainPoolId][mainTokenId].isPaired) {
                uint256 bakcTokenId = mainToBakc[_mainPoolId][mainTokenId].tokenId;
                address currentOwner = nftContracts[BAKC_POOL_ID].ownerOf(bakcTokenId);

                /* Split Pair Check*/
                if (currentOwner != _address) {
                    uint256 deposited = nftPosition[BAKC_POOL_ID][bakcTokenId].stakedAmount;
                    uint256 unclaimed = deposited > 0 ? this.pendingRewards(BAKC_POOL_ID, currentOwner, bakcTokenId) : 0;
                    uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(BAKC_POOL_ID, currentOwner, bakcTokenId): 0;

                    DashboardPair memory pair = NULL_PAIR;
                    if(bakcToMain[bakcTokenId][_mainPoolId].isPaired) {
                        pair = DashboardPair(bakcToMain[bakcTokenId][_mainPoolId].tokenId, _mainPoolId);
                    }

                    DashboardStake memory dashboardStake = DashboardStake(BAKC_POOL_ID, bakcTokenId, deposited, unclaimed, rewards24Hrs, pair);
                    dashboardStakes[counter] = dashboardStake;
                    ++counter;
                }
            }
        }

        return dashboardStakes;
    }

    function _getSplitStakeCount(uint256 nftCount, address _address, uint256 _mainPoolId) private view returns (uint256) {
        uint256 splitCount;
        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 mainTokenId = nftContracts[_mainPoolId].tokenOfOwnerByIndex(_address, i);
            if(mainToBakc[_mainPoolId][mainTokenId].isPaired) {
                uint256 bakcTokenId = mainToBakc[_mainPoolId][mainTokenId].tokenId;
                address currentOwner = nftContracts[BAKC_POOL_ID].ownerOf(bakcTokenId);
                if (currentOwner != _address) {
                    ++splitCount;
                }
            }
        }

        return splitCount;
    }

    function _getStakes(address _address, uint256 _poolId) private view returns (DashboardStake[] memory) {
        uint256 nftCount = nftContracts[_poolId].balanceOf(_address);
        DashboardStake[] memory dashboardStakes = nftCount > 0 ? new DashboardStake[](nftCount) : new DashboardStake[](0);

        if(nftCount == 0) {
            return dashboardStakes;
        }

        for(uint256 i = 0; i < nftCount; ++i) {
            uint256 tokenId = nftContracts[_poolId].tokenOfOwnerByIndex(_address, i);
            uint256 deposited = nftPosition[_poolId][tokenId].stakedAmount;
            uint256 unclaimed = deposited > 0 ? this.pendingRewards(_poolId, _address, tokenId) : 0;
            uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(_poolId, _address, tokenId): 0;

            DashboardPair memory pair = NULL_PAIR;
            if(_poolId == BAKC_POOL_ID) {
                if(bakcToMain[tokenId][BAYC_POOL_ID].isPaired) {
                    pair = DashboardPair(bakcToMain[tokenId][BAYC_POOL_ID].tokenId, BAYC_POOL_ID);
                } else if(bakcToMain[tokenId][MAYC_POOL_ID].isPaired) {
                    pair = DashboardPair(bakcToMain[tokenId][MAYC_POOL_ID].tokenId, MAYC_POOL_ID);
                }
            }

            DashboardStake memory dashboardStake = DashboardStake(_poolId, tokenId, deposited, unclaimed, rewards24Hrs, pair);
            dashboardStakes[i] = dashboardStake;
        }

        return dashboardStakes;
    }

    function _estimate24HourRewards(uint256 _poolId, address _address, uint256 _tokenId) private view returns (uint256) {
        Pool memory pool = pools[_poolId];
        Position memory position = _poolId == 0 ? addressPosition[_address]: nftPosition[_poolId][_tokenId];

        TimeRange memory rewards = getTimeRangeBy(_poolId, pool.lastRewardsRangeIndex);
        return (position.stakedAmount * rewards.rewardsPerHour * 24) / pool.stakedAmount;
    }

    /**
     * @notice Fetches the current amount of claimable ApeCoin rewards for a given position from a given pool.
     * @return uint256 value of pending rewards
     * @param _poolId Available pool values 0-3
     * @param _address Address to lookup Position for
     * @param _tokenId An NFT id
     */
    function pendingRewards(uint256 _poolId, address _address, uint256 _tokenId) external view returns (uint256) {
        Pool memory pool = pools[_poolId];
        Position memory position = _poolId == 0 ? addressPosition[_address]: nftPosition[_poolId][_tokenId];

        (uint256 rewardsSinceLastCalculated,) = rewardsBy(_poolId, pool.lastRewardedTimestampHour, getPreviousTimestampHour());
        uint256 accumulatedRewardsPerShare = pool.accumulatedRewardsPerShare;

        if (block.timestamp > pool.lastRewardedTimestampHour + SECONDS_PER_HOUR && pool.stakedAmount != 0) {
            accumulatedRewardsPerShare = accumulatedRewardsPerShare + rewardsSinceLastCalculated * APE_COIN_PRECISION / pool.stakedAmount;
        }
        return ((position.stakedAmount * accumulatedRewardsPerShare).toInt256() - position.rewardsDebt).toUint256() / APE_COIN_PRECISION;
    }

    // Convenience methods for timestamp calculation

    /// @notice the minutes (0 to 59) of a timestamp
    function getMinute(uint256 timestamp) internal pure returns (uint256 minute) {
        uint256 secs = timestamp % SECONDS_PER_HOUR;
        minute = secs / SECONDS_PER_MINUTE;
    }

    /// @notice the seconds (0 to 59) of a timestamp
    function getSecond(uint256 timestamp) internal pure returns (uint256 second) {
        second = timestamp % SECONDS_PER_MINUTE;
    }

    /// @notice the previous whole hour of a timestamp
    function getPreviousTimestampHour() internal view returns (uint256) {
        return block.timestamp - (getMinute(block.timestamp) * 60 + getSecond(block.timestamp));
    }

    function getAddressPosition(address _recipient)
        external
        view
        returns (Position memory)
    {
        return addressPosition[_recipient];
    }

    function getNftPosition(uint256 _poolId, uint256 _tokenId)
        external
        view
        returns (Position memory)
    {
        return nftPosition[_poolId][_tokenId];
    }

    function getMainToBakc(uint256 _poolId, uint256 _tokenId)
        external
        view
        returns (PairingStatus memory)
    {
        return mainToBakc[_poolId][_tokenId];
    }

    function getBakcToMain(uint256 _tokenId, uint256 _poolId)
        external
        view
        returns (PairingStatus memory)
    {
        return bakcToMain[_tokenId][_poolId];
    }

    // Private Methods - shared logic
    /// @notice trasnferFrom must be called after deposit logic is complete
    // seperating deposit logic and deposit transfer for gas optimization in loops
    function _deposit(uint256 _poolId, Position storage _position, uint256 _amount) private {
        Pool storage pool = pools[_poolId];

        uint80 __amount = uint80(_amount);
        _position.stakedAmount += __amount;
        pool.stakedAmount += __amount;
        _position.rewardsDebt += (
            int256(_amount * uint256(pool.accumulatedRewardsPerShare))
        ).toInt176();
    }

    function _depositNft(uint256 _poolId, SingleNft[] calldata _nfts) private {
        updatePool(_poolId);
        uint256 tokenId;
        uint256 amount;
        Position storage position;
        uint256 len = _nfts.length;
        uint256 totalDeposit;
        for(uint256 i; i < len;) {
            tokenId = _nfts[i].tokenId;
            position = nftPosition[_poolId][tokenId];
            if (position.stakedAmount == 0)
                if (nftContracts[_poolId].ownerOf(tokenId) != msg.sender)
                    revert CallerNotOwner();
            amount = _nfts[i].amount;
            _depositNftGuard(_poolId, position, amount);
            totalDeposit += amount;
            emit DepositNft(msg.sender, _poolId, amount, tokenId);
            unchecked {
                ++i;
            }
        }
        if (totalDeposit > 0)
            /* OPTIMIZE:
             * safeTransferFrom is an overkill, after checking APECOIN ERC20 contract on etherscan,
             * you would notice that it adhere to ERC20 token standard and returns actually true on successful transferFrom
             * or reverts.
             */
            apeCoin.transferFrom(msg.sender, address(this), totalDeposit);
    }

    function _depositPairNft(uint256 mainTypePoolId, PairNftWithAmount[] calldata _nfts) private {
        uint256 len = _nfts.length;
        uint256 totalDeposit;
        PairNftWithAmount memory pair;
        Position storage position;
        for(uint256 i; i < len;) {
            pair = _nfts[i];
            position = nftPosition[BAKC_POOL_ID][pair.bakcTokenId];

            if(position.stakedAmount == 0) {
                if (
                    nftContracts[mainTypePoolId].ownerOf(pair.mainTokenId) !=
                    msg.sender ||
                    mainToBakc[mainTypePoolId][pair.mainTokenId].isPaired
                ) revert TokenNotOwnedOrPaired();
                if (
                    nftContracts[BAKC_POOL_ID].ownerOf(pair.bakcTokenId) !=
                    msg.sender ||
                    bakcToMain[pair.bakcTokenId][mainTypePoolId].isPaired
                ) revert BAKCNotOwnedOrPaired();
                mainToBakc[mainTypePoolId][pair.mainTokenId] = PairingStatus(uint248(pair.bakcTokenId), true);
                bakcToMain[pair.bakcTokenId][mainTypePoolId] = PairingStatus(uint248(pair.mainTokenId), true);
            } else if (
                pair.mainTokenId !=
                bakcToMain[pair.bakcTokenId][mainTypePoolId].tokenId ||
                pair.bakcTokenId !=
                mainToBakc[mainTypePoolId][pair.mainTokenId].tokenId
            ) revert BAKCAlreadyPaired();

            _depositNftGuard(BAKC_POOL_ID, position, pair.amount);
            totalDeposit += pair.amount;
            emit DepositPairNft(msg.sender, pair.amount, mainTypePoolId, pair.mainTokenId, pair.bakcTokenId);
            unchecked {
                ++i;
            }
        }
        if (totalDeposit > 0)
            /* OPTIMIZE:
             * safeTransferFrom is an overkill, after checking APECOIN ERC20 contract on etherscan,
             * you would notice that it adhere to ERC20 token standard and returns actually true on successful transferFrom
             * or reverts.
             */
            apeCoin.transferFrom(msg.sender, address(this), totalDeposit);
    }

    function _depositNftGuard(uint256 _poolId, Position storage _position, uint256 _amount) private {
        if (_amount < MIN_DEPOSIT) revert DepositMoreThanOneAPE();
        if (
            _amount + _position.stakedAmount >
            pools[_poolId]
                .timeRanges[pools[_poolId].lastRewardsRangeIndex]
                .capPerPosition
        ) revert ExceededCapAmount();
        _deposit(_poolId, _position, _amount);
    }

    function _claim(uint256 _poolId, Position storage _position, address _recipient) private returns (uint256 rewardsToBeClaimed) {
        Pool storage pool = pools[_poolId];

        int256 accumulatedApeCoins = (uint256(_position.stakedAmount) *
            pool.accumulatedRewardsPerShare).toInt256();
        rewardsToBeClaimed = (accumulatedApeCoins - _position.rewardsDebt).toUint256() / APE_COIN_PRECISION;

        _position.rewardsDebt = (accumulatedApeCoins).toInt176();

        // SafeTransfer is an overkill, after checking APECOIN ERC20 contract on etherscan,
        // you would notice that it adhere to ERC20 token standard and returns actually true on successful transfer
        // or reverts.

        if (rewardsToBeClaimed != 0) {
            apeCoin.transfer(_recipient, rewardsToBeClaimed);
        }
    }

    function _claimNft(uint256 _poolId, uint256[] calldata _nfts, address _recipient) private {
        updatePool(_poolId);
        uint256 tokenId;
        uint256 rewardsToBeClaimed;
        uint256 len = _nfts.length;
        for(uint256 i; i < len;) {
            tokenId = _nfts[i];
            if (nftContracts[_poolId].ownerOf(tokenId) != msg.sender)
                revert CallerNotOwner();
            Position storage position = nftPosition[_poolId][tokenId];
            rewardsToBeClaimed = _claim(_poolId, position, _recipient);
            emit ClaimRewardsNft(msg.sender, _poolId, rewardsToBeClaimed, tokenId);
            unchecked {
                ++i;
            }
        }
    }

    function _claimPairNft(uint256 mainTypePoolId, PairNft[] calldata _pairs, address _recipient) private {
        uint256 len = _pairs.length;
        uint256 mainTokenId;
        uint256 bakcTokenId;
        Position storage position;
        PairingStatus storage mainToSecond;
        PairingStatus storage secondToMain;
        for(uint256 i; i < len;) {
            mainTokenId = _pairs[i].mainTokenId;
            if (
                nftContracts[mainTypePoolId].ownerOf(mainTokenId) !=
                msg.sender
            ) revert NotOwnerOfMain();

            bakcTokenId = _pairs[i].bakcTokenId;

            if (
                nftContracts[BAKC_POOL_ID].ownerOf(bakcTokenId) !=
                msg.sender
            ) revert NotOwnerOfBAKC();

            mainToSecond = mainToBakc[mainTypePoolId][mainTokenId];
            secondToMain = bakcToMain[bakcTokenId][mainTypePoolId];

            if (
                mainToSecond.tokenId != bakcTokenId ||
                !mainToSecond.isPaired ||
                secondToMain.tokenId != mainTokenId ||
                !secondToMain.isPaired
            ) revert ProvidedTokensNotPaired();

            position = nftPosition[BAKC_POOL_ID][bakcTokenId];

            uint256 rewardsToBeClaimed = _claim(BAKC_POOL_ID, position, _recipient);
            emit ClaimRewardsPairNft(msg.sender, rewardsToBeClaimed, mainTypePoolId, mainTokenId, bakcTokenId);
            unchecked {
                ++i;
            }
        }
    }
    /// @notice trasnfer must be called after withdraw logic is complete
    // seperating withdraw logic and withdraw transfer for gas optimization in loops
    function _withdraw(uint256 _poolId, Position storage _position, uint256 _amount) private {
        if (_amount > _position.stakedAmount) revert ExceededStakedAmount();

        Pool storage pool = pools[_poolId];

        uint80 _amount_ = uint80(_amount);
        _position.stakedAmount -= _amount_;
        pool.stakedAmount -= _amount_;
        _position.rewardsDebt -= (
            int256(_amount * pool.accumulatedRewardsPerShare)
        ).toInt176();
    }

    function _withdrawNft(uint256 _poolId, SingleNft[] calldata _nfts, address _recipient) private {
        updatePool(_poolId);
        uint256 tokenId;
        uint256 amount;
        uint256 len = _nfts.length; // OTPIMIZE: asigning variable to memory, to avoid being called on each iteration
        uint256 totalWithdraw;
        Position storage position;
        for(uint256 i; i < len;) {
            tokenId = _nfts[i].tokenId;
            if (nftContracts[_poolId].ownerOf(tokenId) != msg.sender)
                revert CallerNotOwner();
            amount = _nfts[i].amount;
            position = nftPosition[_poolId][tokenId];
            if (amount == position.stakedAmount) {
                uint256 rewardsToBeClaimed = _claim(_poolId, position, _recipient);
                emit ClaimRewardsNft(msg.sender, _poolId, rewardsToBeClaimed, tokenId);
            }
            _withdraw(_poolId, position, amount);
            totalWithdraw += amount;
            emit WithdrawNft(msg.sender, _poolId, amount, _recipient, tokenId);
            unchecked {
                ++i;
            }
        }
        // OPTIMIZE: external call only once
        // SafeTransfer is an overkill, after checking APECOIN ERC20 contract on etherscan,
        // you would notice that it adhere to ERC20 token standard and returns actually true on successful transfer
        // or reverts.
        if (totalWithdraw > 0) apeCoin.transfer(_recipient, totalWithdraw);
    }

    function _withdrawPairNft(uint256 mainTypePoolId, PairNftWithAmount[] calldata _nfts) private {
        address mainTokenOwner;
        address bakcOwner;
        PairNftWithAmount memory pair;
        PairingStatus storage mainToSecond; //OPTIMIZE: referencing storage is cheaper than copying to memory each time
        PairingStatus storage secondToMain; //OPTIMIZE: referencing storage is cheaper than copying to memory each time
        Position storage position;
        uint256 len = _nfts.length;
        for(uint256 i; i < len;) {
            pair = _nfts[i];
            mainTokenOwner = nftContracts[mainTypePoolId].ownerOf(pair.mainTokenId);
            bakcOwner = nftContracts[BAKC_POOL_ID].ownerOf(pair.bakcTokenId);

            if (mainTokenOwner != msg.sender)
                if (bakcOwner != msg.sender) revert CallerNotTokenOwnerInPair();
            mainToSecond = mainToBakc[mainTypePoolId][pair.mainTokenId];
            secondToMain = bakcToMain[pair.bakcTokenId][mainTypePoolId];
            if (
                mainToSecond.tokenId != pair.bakcTokenId ||
                !mainToSecond.isPaired ||
                secondToMain.tokenId != pair.mainTokenId ||
                !secondToMain.isPaired
            ) revert ProvidedTokensNotPaired();
            position = nftPosition[BAKC_POOL_ID][pair.bakcTokenId];
            if (mainTokenOwner != bakcOwner)
                if (pair.amount != position.stakedAmount)
                    revert SplitPairCantPartiallyWithdraw();

            if (pair.amount == position.stakedAmount) {
                uint256 rewardsToBeClaimed = _claim(BAKC_POOL_ID, position, bakcOwner);
                mainToBakc[mainTypePoolId][pair.mainTokenId] = PairingStatus(0, false);
                bakcToMain[pair.bakcTokenId][mainTypePoolId] = PairingStatus(0, false);
                emit ClaimRewardsPairNft(msg.sender, rewardsToBeClaimed, mainTypePoolId, pair.mainTokenId, pair.bakcTokenId);
            }
            _withdraw(BAKC_POOL_ID, position, pair.amount);
            // SafeTransfer is an overkill, after checking APECOIN ERC20 contract on etherscan,
            // you would notice that it adhere to ERC20 token standard and returns actually true on successful transfer
            // or reverts.
            apeCoin.transfer(mainTokenOwner, pair.amount);
            emit WithdrawPairNft(msg.sender, pair.amount, mainTypePoolId, pair.mainTokenId, pair.bakcTokenId);
            unchecked {
                ++i;
            }
        }
    }

}
