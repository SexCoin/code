// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SexCoin is ERC20, Ownable, ReentrancyGuard, VRFConsumerBase {
    using SafeERC20 for IERC20;

    // Chainlink VRF variables
    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public randomResult;
    mapping(bytes32 => address) public requestToSender;

    // Chainlink Price Feed
    mapping(address => address) public tokenPriceFeeds; // Mapeamento de tokens para seus Price Feeds

    // Token distribution settings
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10**18;
    uint256 public constant CREATOR_SUPPLY = 1_000_000 * 10**18;
    uint256 public constant DEVELOPMENT_SUPPLY = 1_000_000 * 10**18;
    uint256 public constant PROMOTIONAL_SUPPLY = 3_000_000 * 10**18;
    uint256 public constant STAKING_SUPPLY = 10_000_000 * 10**18;
    uint256 public constant LIQUIDITY_SUPPLY = 5_000_000 * 10**18;
    uint256 public constant MINING_SUPPLY = 75_000_000 * 10**18;
    uint256 public constant PRESALE_SUPPLY = 5_000_000 * 10**18;

    // Configurable addresses
    address public creatorAddress;
    address public developmentAddress;
    address public promotionalAddress;
    address public liquidityPool;

    // Presale variables
    mapping(address => uint256) public presaleContributions;
    uint256 public presaleTotalContribution;
    bool public presaleActive;

    // Preço fixo de 1 SEX em USDT (0,05 USDT)
    uint256 public constant SEX_PRICE_USDT = 0.05 * 10**18; // 0,05 USDT com 18 casas decimais

    // Control variables
    uint256 private _minedSupply;
    uint256 private _stakingSupply = STAKING_SUPPLY;
    uint256 private _liquiditySupply = LIQUIDITY_SUPPLY;

    // Staking and HODLing
    struct StakingInfo {
        uint256 amount;
        uint256 stakingStartTime;
    }
    mapping(address => StakingInfo) public stakingBalances;
    uint256 public constant STAKING_APY = 10;
    uint256 public constant HODLING_APY = 5;
    uint256 public constant SECONDS_IN_YEAR = 31536000;

    // Mining
    uint256 public constant INITIAL_MINING_RATE = 50 * 10**18;
    uint256 private _miningRate;
    uint256 private _lastHalvingTimestamp;
    uint256 private _miningDifficulty;
    mapping(address => uint256) private _lastMiningTimestamp;
    mapping(address => uint256) private _minedTokens;
    uint256 public constant MAX_TOKENS_PER_ADDRESS = 1000 * 10**18;

    // Liquidity
    uint256 public constant LIQUIDITY_FEE_PERCENT = 2;

    // Staking commit-reveal
    struct StakingCommit {
        uint256 amount;
        uint256 commitTime;
        bool revealed;
    }
    mapping(address => StakingCommit) public stakingCommits;
    uint256 public constant COMMIT_REVEAL_DELAY = 1 minutes;

    // Gamification
    mapping(address => uint256) public miningPoints;
    uint256 public constant POINTS_PER_MINE = 10;

    // NFTs
    uint256 public constant INITIAL_NFT_SUPPLY = 10_000;
    uint256 public constant EXTENDED_NFT_SUPPLY = 40_000;
    uint256 private _nextTokenId = 1;
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => address) private _owners;
    uint256 public constant NFT_MINT_COST = 100 * 10**18;
    uint256 public constant NFT_DEVELOPMENT_FEE_PERCENT = 3;
    uint256 public constant NFT_LIQUIDITY_FEE_PERCENT = 97;

    // Events
    event NFTMinted(address indexed to, uint256 indexed tokenId, string tokenURI);
    event PresaleContribution(address indexed contributor, address indexed token, uint256 amount, uint256 tokens);
    event RandomNumberRequested(bytes32 requestId);
    event RandomNumberReceived(bytes32 requestId, uint256 randomNumber);
    event GasPriceAdjusted(uint256 oldPrice, uint256 newPrice);
    event StakingStarted(address indexed user, uint256 amount);
    event StakingEnded(address indexed user, uint256 amount, uint256 rewards);
    event TokenPriceFeedSet(address indexed token, address indexed priceFeed);

    // Mapping to limit transfers per address
    mapping(address => uint256) public lastTransferTimestamp;
    uint256 public constant TRANSFER_COOLDOWN = 1 minutes;

    // Minimum gas price
    uint256 public minGasPrice;

    constructor(
        address _creatorAddress,
        address _developmentAddress,
        address _promotionalAddress,
        address _vrfCoordinator,
        address _linkToken,
        bytes32 _keyHash,
        uint256 _fee,
        address _defaultPriceFeed // Endereço do Chainlink Price Feed padrão (USDT/USDT)
    ) ERC20("Sex Coin", "SEX") VRFConsumerBase(_vrfCoordinator, _linkToken) Ownable(msg.sender) {
        require(_creatorAddress != address(0), "Invalid creator address");
        require(_developmentAddress != address(0), "Invalid development address");
        require(_promotionalAddress != address(0), "Invalid promotional address");

        creatorAddress = _creatorAddress;
        developmentAddress = _developmentAddress;
        promotionalAddress = _promotionalAddress;

        // Initialize Chainlink VRF
        keyHash = _keyHash;
        fee = _fee;

        // Define o Price Feed padrão (USDT/USDT)
        tokenPriceFeeds[address(0)] = _defaultPriceFeed; // address(0) representa MATIC/POL

        // Mint initial tokens
        _mint(creatorAddress, CREATOR_SUPPLY);
        _mint(developmentAddress, DEVELOPMENT_SUPPLY);
        _mint(promotionalAddress, PROMOTIONAL_SUPPLY);
        _mint(address(this), STAKING_SUPPLY + LIQUIDITY_SUPPLY + PRESALE_SUPPLY);

        // Initialize mining variables
        _lastHalvingTimestamp = block.timestamp;
        _miningRate = INITIAL_MINING_RATE;
        _miningDifficulty = 1 minutes;

        // Set a default minimum gas price
        minGasPrice = 10 gwei;

        // Activate presale
        presaleActive = true;
    }

    // ===================== CHAINLINK VRF =====================
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        require(randomness > 0, "Invalid random number");
        randomResult = randomness; // Armazena o número aleatório
        emit RandomNumberReceived(requestId, randomness); // Emite um evento
    }

    // ===================== PRESALE =====================
    function setTokenPriceFeed(address token, address priceFeed) public onlyOwner {
        require(token != address(0), "Invalid token address");
        require(priceFeed != address(0), "Invalid price feed address");

        tokenPriceFeeds[token] = priceFeed;
        emit TokenPriceFeedSet(token, priceFeed);
    }

    function getTokenPriceUSDT(address token) internal view returns (uint256) {
        // Obtém o endereço do Price Feed para o token
        address priceFeedAddress = tokenPriceFeeds[token];
        require(priceFeedAddress != address(0), "Price feed not set for token");

        // Obtém o preço do token em relação ao USDT
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");

        // Retorna o preço com 18 casas decimais
        return uint256(price);
    }

    function contributeToPresale(address token, uint256 amount) public payable nonReentrant {
        require(presaleActive, "Presale is not active");
        require(amount > 0, "Amount must be greater than 0");

        // Obtém o valor do token em relação ao USDT
        uint256 tokenPriceUSDT = getTokenPriceUSDT(token);
        require(tokenPriceUSDT > 0, "Invalid token price");

        // Calcula o valor total em USDT
        uint256 totalValueUSDT = (amount * tokenPriceUSDT) / 10**18;

        // Calcula a quantidade de SEX a ser distribuída (1 SEX = 0,05 USDT)
        uint256 tokens = (totalValueUSDT * 10**18) / SEX_PRICE_USDT;
        require(presaleTotalContribution + tokens <= PRESALE_SUPPLY, "Presale supply exhausted");

        // Transfere os tokens do usuário para o contrato
        if (token == address(0)) {
            // Se o token for MATIC/POL, use msg.value
            require(msg.value == amount, "Invalid MATIC amount");
            payable(address(this)).transfer(msg.value);
        } else {
            // Se for um token ERC20, transfira normalmente
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Atualiza as contribuições da Presale
        presaleContributions[msg.sender] += tokens;
        presaleTotalContribution += tokens;

        // Transfere os tokens SEX para o contribuidor
        _transfer(address(this), msg.sender, tokens);

        emit PresaleContribution(msg.sender, token, amount, tokens);
    }

    function endPresale() public onlyOwner {
        presaleActive = false;
    }

    // ===================== OUTRAS FUNÇÕES =====================
    // (O restante do código permanece inalterado)
}
