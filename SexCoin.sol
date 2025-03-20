// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

contract SexCoin is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using AddressUpgradeable for address;

    // ======================
    // Estruturas e Variáveis
    // ======================

    // Endereços dos contratos
    address public miningContractAddress; // Contrato de mineração
    address public developmentFundAddress; // Endereço de desenvolvimento
    address public marketingFundAddress; // Endereço promocional
    address public liquidityPoolAddress; // Contrato de pool de liquidez
    address public presaleContractAddress; // Endereço do contrato de presale
    address public stakeContractAddress; // Endereço do contrato de stake
    address public nftContractAddress; // Endereço do contrato de NFTs
    address public governanceContractAddress; // Endereço do contrato de governança
    address public donationContractAddress; // Endereço do contrato de doações

    // Totais de supply
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10**18;
    uint256 public constant PRESALE_SUPPLY = 5_000_000 * 10**18; // Para presale (pool de liquidez)
    uint256 public constant DEVELOPMENT_SUPPLY = 1_000_000 * 10**18; // Para desenvolvimento
    uint256 public constant MARKETING_SUPPLY = 5_000_000 * 10**18; // Para promoções
    uint256 public constant CREATOR_TOTAL_SUPPLY = 1_000_000 * 10**18; // Total alocado ao criador
    uint256 public constant STAKE_SUPPLY = 5_000_000 * 10**18; // Para stake
    uint256 public constant NFT_SUPPLY = 500_000 * 10**18; // Para NFTs
    uint256 public constant DONATION_SUPPLY = 2_500_000 * 10**18; // Para doações (governança)
    uint256 public constant MINING_SUPPLY = 80_000_000 * 10**18; // Para mineração

    // Distribuição para o criador
    uint256 public constant CREATOR_INITIAL_SUPPLY = 250_000 * 10**18; // 250k na criação
    uint256 public constant CREATOR_VESTING_SUPPLY = 250_000 * 10**18; // 250k por período de vesting
    uint256 public constant CREATOR_VESTING_PERIODS = 3; // 3 períodos de vesting
    uint256 public creatorVestingStartTime;
    uint256 public creatorVestingCount;

    // Controle de distribuição inicial
    bool public isInitialSupplyDistributed;

    // Controle de mineração
    mapping(address => uint256) public lastMineBlock;
    mapping(address => uint256) public lastMineTime; // Tempo da última mineração
    mapping(address => uint256) public minerContributions; // Rastreia as contribuições dos mineradores
    uint256 public totalMinedTokens; // Total de tokens já minerados
    uint256 public maxTokensPerBlock; // Limite máximo de tokens minerados por bloco

    // Rastreamento de tokens queimados
    uint256 public burnedSupply;

    // Taxa de queima (1% por padrão)
    uint256 public burnRate; // Taxa de queima em porcentagem (1 = 1%)
    uint256 public constant MAX_BURN_RATE = 10; // Taxa máxima de queima (10%)

    // Lista de implementações aprovadas para upgrades
    mapping(address => bool) public approvedImplementations;

    // Controle de upgrades
    uint256 public upgradeDelay = 1 days;
    mapping(address => uint256) public upgradeRequestTime;
    mapping(address => bool) public upgradeConfirmed; // Confirmação de upgrade

    // Tempo mínimo entre tentativas de mineração
    uint256 public constant MINING_COOLDOWN = 10 minutes;

    // Eventos
    event TokensMined(address indexed miner, uint256 amount);
    event TokensBurned(address indexed burner, uint256 amount);
    event InitialSupplyDistributed(
        address indexed miningContract,
        address indexed developmentFund,
        address indexed marketingFund,
        address presaleContract,
        address stakeContract,
        address nftContract,
        address governanceContract,
        address donationContract
    );
    event CreatorTokensWithdrawn(address indexed creator, uint256 amount);
    event DonationSent(address indexed donationContract, uint256 amount);
    event ContractInitialized(uint8 contractType, address contractAddress);
    event ContractAddressUpdated(uint8 contractType, address newAddress);
    event GovernanceTransferred(address indexed governanceContract);
    event ImplementationApproved(address indexed implementation);
    event UpgradeRequested(address indexed newImplementation, uint256 requestTime);
    event BurnRateUpdated(uint256 newBurnRate);
    event MaxTokensPerBlockUpdated(uint256 newMaxTokensPerBlock);

    // Papéis de controle de acesso
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ======================
    // Inicialização
    // ======================

    /**
     * @dev Inicializa o contrato principal.
     */
    function initialize() public initializer {
        require(msg.sender == tx.origin, unicode"Contratos não podem chamar initialize");

        __ERC20_init("Sex Coin", "SEX");
        __AccessControl_init();
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        // Define a taxa de queima inicial (1%)
        burnRate = 1;

        // Define o limite máximo de tokens minerados por bloco
        maxTokensPerBlock = 1000 * 10**18;

        // Distribuição inicial de tokens para o criador
        _mint(msg.sender, CREATOR_INITIAL_SUPPLY);
        creatorVestingStartTime = block.timestamp;
        creatorVestingCount = 0;
    }

    // ======================
    // Funções de Distribuição
    // ======================

    /**
     * @dev Distribui o fornecimento inicial de tokens para os contratos auxiliares.
     */
    function distributeInitialSupply() external onlyOwner {
        require(!isInitialSupplyDistributed, unicode"Distribuição já realizada");

        require(miningContractAddress.isContract(), unicode"Contrato de mineração inválido");
        require(developmentFundAddress.isContract(), unicode"Contrato de desenvolvimento inválido");
        require(marketingFundAddress.isContract(), unicode"Contrato de marketing inválido");
        require(stakeContractAddress.isContract(), unicode"Contrato de stake inválido");
        require(nftContractAddress.isContract(), unicode"Contrato de NFTs inválido");
        require(donationContractAddress.isContract(), unicode"Contrato de doações inválido");
        require(presaleContractAddress.isContract(), unicode"Contrato de presale inválido");

        _mint(developmentFundAddress, DEVELOPMENT_SUPPLY);
        _mint(marketingFundAddress, MARKETING_SUPPLY);
        _mint(stakeContractAddress, STAKE_SUPPLY);
        _mint(nftContractAddress, NFT_SUPPLY);
        _mint(donationContractAddress, DONATION_SUPPLY);
        _mint(miningContractAddress, MINING_SUPPLY);
        _mint(presaleContractAddress, PRESALE_SUPPLY);

        isInitialSupplyDistributed = true;

        emit InitialSupplyDistributed(
            miningContractAddress,
            developmentFundAddress,
            marketingFundAddress,
            presaleContractAddress,
            stakeContractAddress,
            nftContractAddress,
            governanceContractAddress,
            donationContractAddress
        );
    }

    // ======================
    // Funções de Mineração
    // ======================

    /**
     * @dev Função para minerar novos tokens (modelo semelhante ao Bitcoin).
     */
    function mineTokens(uint256 amount) external onlyRole(MINTER_ROLE) nonReentrant whenNotPaused {
        require(amount > 0, unicode"Quantidade deve ser maior que zero");
        require(totalSupply() + burnedSupply + amount <= TOTAL_SUPPLY, unicode"Excede o fornecimento total, considere tokens queimados");
        require(block.number > lastMineBlock[msg.sender], unicode"Espere o próximo bloco");

        // Verifica se o minerador contribuiu para a rede
        require(minerContributions[msg.sender] > 0, unicode"Contribuição insuficiente para minerar");

        // Verifica o tempo mínimo entre minerações
        require(block.timestamp >= lastMineTime[msg.sender] + MINING_COOLDOWN, unicode"Espere antes de minerar novamente");

        uint256 currentBlock = block.number;
        uint256 halvingInterval = 210_000; // Ajuste o intervalo de halving
        uint256 halvingCount = currentBlock / halvingInterval;
        uint256 reward = 50 * 10**18 / (2 ** halvingCount); // Recompensa inicial de 50 tokens, reduzida pela metade a cada halving

        // Definir um mínimo de 0.1 SEX
        uint256 minReward = 0.1 * 10**18;
        reward = reward < minReward ? minReward : reward;

        require(amount <= reward, unicode"Excede a recompensa atual de mineração");
        require(amount <= maxTokensPerBlock, unicode"Excede o limite de tokens por bloco");
        require(totalMinedTokens + amount <= MINING_SUPPLY, unicode"Limite de mineração atingido");

        // Aplica a taxa de queima
        uint256 burnAmount = (amount * burnRate) / 100;
        if (burnAmount > 0) {
            _burn(msg.sender, burnAmount);
            burnedSupply += burnAmount;
            emit TokensBurned(msg.sender, burnAmount);
        }

        lastMineBlock[msg.sender] = block.number;
        lastMineTime[msg.sender] = block.timestamp;
        totalMinedTokens += amount;
        _mint(msg.sender, amount - burnAmount);
        emit TokensMined(msg.sender, amount - burnAmount);
    }

    /**
     * @dev Define o limite máximo de tokens minerados por bloco.
     */
    function setMaxTokensPerBlock(uint256 newMaxTokensPerBlock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMaxTokensPerBlock > 0, unicode"O limite deve ser maior que zero");
        maxTokensPerBlock = newMaxTokensPerBlock;
        emit MaxTokensPerBlockUpdated(newMaxTokensPerBlock);
    }

    // ======================
    // Funções de Vesting
    // ======================

    /**
     * @dev Função para o criador sacar tokens vesting.
     */
    function withdrawCreatorTokens() external nonReentrant {
        require(msg.sender == owner(), unicode"Apenas o criador pode sacar");
        require(creatorVestingCount < CREATOR_VESTING_PERIODS, unicode"Todos os tokens vesting já foram sacados");
        require(totalSupply() + burnedSupply + CREATOR_VESTING_SUPPLY <= TOTAL_SUPPLY, unicode"Excede o fornecimento total, considere tokens queimados");
        require(creatorVestingStartTime > 0, unicode"Vesting ainda não iniciou");

        uint256 nextVestingTime = creatorVestingStartTime + (creatorVestingCount + 1) * 365 days;
        require(block.timestamp >= nextVestingTime, 
            string(abi.encodePacked("Aguarde ", (nextVestingTime - block.timestamp) / 1 days, " dias")));

        // Proteção contra overflow
        require(creatorVestingCount + 1 > creatorVestingCount, unicode"Overflow no contador de vesting");

        creatorVestingCount++;
        _mint(msg.sender, CREATOR_VESTING_SUPPLY);
        emit CreatorTokensWithdrawn(msg.sender, CREATOR_VESTING_SUPPLY);
    }

    // ======================
    // Funções de Queima de Tokens
    // ======================

    /**
     * @dev Função para queimar tokens.
     */
    function burn(uint256 amount) external nonReentrant {
        require(amount > 0, unicode"Quantidade deve ser maior que zero");
        require(balanceOf(msg.sender) >= amount, unicode"Saldo insuficiente");

        _burn(msg.sender, amount);
        burnedSupply += amount;
        emit TokensBurned(msg.sender, amount);
    }

    /**
     * @dev Define a taxa de queima.
     */
    function setBurnRate(uint256 newBurnRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newBurnRate <= MAX_BURN_RATE, unicode"Taxa de queima excede o limite máximo");
        burnRate = newBurnRate;
        emit BurnRateUpdated(newBurnRate);
    }

    // ======================
    // Funções de Upgrade
    // ======================

    /**
     * @dev Adiciona uma implementação à lista de aprovadas para upgrades.
     */
    function approveImplementation(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newImplementation.isContract(), unicode"Endereço inválido");
        approvedImplementations[newImplementation] = true;
        emit ImplementationApproved(newImplementation);
    }

    /**
     * @dev Função para solicitar um upgrade.
     */
    function requestUpgrade(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newImplementation.isContract(), unicode"Endereço inválido");
        upgradeRequestTime[newImplementation] = block.timestamp;
        upgradeConfirmed[newImplementation] = false; // Requer confirmação
        emit UpgradeRequested(newImplementation, block.timestamp);
    }

    /**
     * @dev Confirma um upgrade após o período de espera.
     */
    function confirmUpgrade(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(approvedImplementations[newImplementation], unicode"Upgrade não autorizado");
        require(block.timestamp >= upgradeRequestTime[newImplementation] + upgradeDelay, unicode"Tempo de espera não concluído");
        upgradeConfirmed[newImplementation] = true;
    }

    /**
     * @dev Função interna para autorizar upgrades. Apenas o DEFAULT_ADMIN_ROLE pode realizar upgrades.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) view {
        require(approvedImplementations[newImplementation], unicode"Upgrade não autorizado");
        require(upgradeConfirmed[newImplementation], unicode"Upgrade não confirmado");
    }
}


