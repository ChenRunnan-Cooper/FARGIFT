// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 导入OpenZeppelin库
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title Present
 * @dev 礼物包装、拆包和收回系统
 * 允许用户将ETH和ERC20代币打包成礼物，指定接收者或允许任何人领取
 */

// 修改后的NFT接口，支持传递完整礼物信息
interface IWrappedPresentNFT {
    function mint(
        address to, 
        bytes32 presentId,
        string memory giftTitle,
        string memory giftMessage,
        uint256 ethValue,
        address creator
    ) external returns (uint256);
}

interface IUnwrappedPresentNFT {
    function mint(
        address to, 
        bytes32 presentId,
        string memory giftTitle,
        string memory giftMessage,
        uint256 ethValue,
        address creator,
        uint256 tokenAmount
    ) external returns (uint256);
}

contract Present is Ownable, ReentrancyGuard, Pausable, IERC721Receiver {
    using SafeERC20 for IERC20;

    event WrapPresent(bytes32 indexed presentId, address sender);
    event UnwrapPresent(bytes32 indexed presentId, address taker);
    event TakeBack(bytes32 indexed presentId, address sender);
    event WrapPresentTest(bytes32 indexed presentId, address sender);
    event UnwrapPresentTest(bytes32 indexed presentId, address taker);
    event TakeBackTest(bytes32 indexed presentId, address sender);
    event PresentExpired(bytes32 indexed presentId, address indexed sender);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);
    event TokenBlacklisted(address indexed token, bool status);
    event ConfigUpdated(string indexed paramName, uint256 oldValue, uint256 newValue);

    struct Asset {
        address tokens;
        uint256 amounts;
    }

    struct PresentInfo {
        bytes32 id;
        address sender;
        address[] recipients;      // 空数组表示公开
        Asset[] content;
        string title;
        string description;
        uint8 status;              // 0 active, 1 unwrapped, 2 takenBack, 3 expired
        uint256 createdAt;
        uint256 expiryAt;
    }

    uint8 private constant PRESENT_ACTIVE = 0;
    uint8 private constant PRESENT_UNWRAPPED = 1;
    uint8 private constant PRESENT_TAKEN_BACK = 2;
    uint8 private constant PRESENT_EXPIRED = 3;

    uint256 public maxAssetCount = 20;
    uint256 public maxRecipientCount = 100;
    uint256 public defaultExpiryPeriod = 365 days;
    uint256 public minValueForGiftDisplay = 0;

    // 仅保留集中式存储
    mapping(bytes32 => PresentInfo) public presents;

    // 代币安全
    mapping(address => bool) public blacklistedTokens;

    // 统计信息
    uint256 public totalPresentsWrapped;
    uint256 public totalPresentsUnwrapped;
    uint256 public totalPresentsTakenBack;
    uint256 public totalPresentsExpired;
    mapping(address => uint256) public userWrappedCount;
    mapping(address => uint256) public userUnwrappedCount;

    // 外部NFT合约地址
    address public wrappedNFT;
    address public unwrappedNFT;

    constructor(address initialOwner) Ownable(initialOwner) {}

    // 仅根据集中式存储判断是否存在
    modifier presentExists(bytes32 presentId) {
        require(presents[presentId].sender != address(0), "Present does not exist");
        _;
    }

    modifier canUnwrap(bytes32 presentId) {
        if (_isExpired(presentId)) {
            _setStatus(presentId, PRESENT_EXPIRED);
            totalPresentsExpired++;
            emit PresentExpired(presentId, _getSender(presentId));
            revert("Present has expired");
        }
        uint8 status = _getStatus(presentId);
        require(status == PRESENT_ACTIVE, "Present cannot be unwrapped");
        _;
    }

    modifier onlySender(bytes32 presentId) {
        require(_getSender(presentId) == msg.sender, "Only sender can call this function");
        _;
    }

    modifier onlyRecipient(bytes32 presentId) {
        address[] memory recipients = _getRecipients(presentId);
        bool isRecipient = recipients.length == 0; // 公开
        if (!isRecipient) {
            for (uint i = 0; i < recipients.length; i++) {
                if (recipients[i] == msg.sender) { isRecipient = true; break; }
            }
        }
        require(isRecipient, "Only recipient can unwrap this present");
        _;
    }

    modifier tokenNotBlacklisted(address token) {
        if (token != address(0)) {
            require(!blacklistedTokens[token], "Token blacklisted");
        }
        _;
    }

    function wrapPresent(address[] calldata recipients, Asset[] calldata content)
        external payable nonReentrant whenNotPaused
    {
        _wrap({recipients: recipients, title: "", description: "", content: content, emitTest: false});
    }

    function wrapPresentTest(
        address[] calldata recipients,
        string calldata title,
        string calldata description,
        Asset[] calldata content
    ) external payable nonReentrant whenNotPaused {
        _wrap({recipients: recipients, title: title, description: description, content: content, emitTest: true});
    }

    function _wrap(
        address[] calldata recipients,
        string memory title,
        string memory description,
        Asset[] calldata content,
        bool emitTest
    ) internal {
        require(content.length > 0 && content.length <= maxAssetCount, "Invalid content size");
        require(recipients.length <= maxRecipientCount, "Too many recipients");

        uint256 ethValue = 0;
        for (uint i = 0; i < content.length; i++) {
            require(!blacklistedTokens[content[i].tokens], "Contains blacklisted token");
            if (content[i].tokens == address(0)) { ethValue += content[i].amounts; }
            require(content[i].amounts > 0, "Amount must be positive");
        }
        require(msg.value >= ethValue, "Insufficient ETH sent");

        bytes32 presentId = generatePresentId(recipients, content);
        require(presents[presentId].sender == address(0), "Present ID exists");

        // 托管 ERC20
        for (uint i = 0; i < content.length; i++) {
            if (content[i].tokens != address(0)) {
                IERC20(content[i].tokens).safeTransferFrom(msg.sender, address(this), content[i].amounts);
            }
        }

        // 写入存储
        PresentInfo storage p = presents[presentId];
        p.id = presentId;
        p.sender = msg.sender;
        p.recipients = recipients;
        p.title = title;
        p.description = description;
        p.status = PRESENT_ACTIVE;
        p.createdAt = block.timestamp;
        p.expiryAt = block.timestamp + defaultExpiryPeriod;
        for (uint i2 = 0; i2 < content.length; i2++) { p.content.push(content[i2]); }

        totalPresentsWrapped++;
        userWrappedCount[msg.sender]++;

        // 修改：传递完整的礼物信息给NFT合约
        if (wrappedNFT != address(0)) {
            string memory giftTitle = bytes(title).length > 0 ? title : "Wrapped Present";
            string memory giftMessage = bytes(description).length > 0 ? description : "A wrapped gift waiting to be opened!";
            
            IWrappedPresentNFT(wrappedNFT).mint(
                msg.sender, 
                presentId,
                giftTitle,
                giftMessage,
                ethValue,
                msg.sender
            );
        }

        if (emitTest) emit WrapPresentTest(presentId, msg.sender);
        else emit WrapPresent(presentId, msg.sender);

        if (msg.value > ethValue) {
            (bool success, ) = msg.sender.call{value: msg.value - ethValue}("");
            require(success, "ETH refund failed");
        }
    }

    function unwrapPresent(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) canUnwrap(presentId) onlyRecipient(presentId)
    {
        _unwrap(presentId, false);
    }

    function unwrapPresentTest(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) canUnwrap(presentId) onlyRecipient(presentId)
    {
        _unwrap(presentId, true);
    }

    function _unwrap(bytes32 presentId, bool isTest) internal {
        PresentInfo storage present = presents[presentId];
        
        _setStatus(presentId, PRESENT_UNWRAPPED);
        totalPresentsUnwrapped++;
        userUnwrappedCount[msg.sender]++;
        
        // 计算总代币价值（用于NFT显示）
        uint256 totalTokenAmount = _calculateTotalTokenAmount(presentId);
        
        _transferAssets(presentId, msg.sender);
        
        // 修改：传递完整信息给拆包NFT合约
        if (unwrappedNFT != address(0)) {
            string memory giftTitle = bytes(present.title).length > 0 ? present.title : "Unwrapped Present";
            string memory giftMessage = bytes(present.description).length > 0 ? present.description : "A gift has been unwrapped!";
            
            // 计算ETH价值
            uint256 ethValue = 0;
            for (uint i = 0; i < present.content.length; i++) {
                if (present.content[i].tokens == address(0)) {
                    ethValue += present.content[i].amounts;
                }
            }
            
            IUnwrappedPresentNFT(unwrappedNFT).mint(
                msg.sender, 
                presentId,
                giftTitle,
                giftMessage,
                ethValue,
                present.sender,
                totalTokenAmount
            );
        }
        
        if (isTest) emit UnwrapPresentTest(presentId, msg.sender);
        else emit UnwrapPresent(presentId, msg.sender);
    }

    // 新增：计算总代币价值的辅助函数
    function _calculateTotalTokenAmount(bytes32 presentId) internal view returns (uint256) {
        Asset[] memory assets = presents[presentId].content;
        uint256 totalTokenAmount = 0;
        
        for (uint i = 0; i < assets.length; i++) {
            if (assets[i].tokens != address(0)) {
                totalTokenAmount += assets[i].amounts;
            }
        }
        
        return totalTokenAmount;
    }

    function takeBack(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) onlySender(presentId)
    {
        require(_canTakeBack(presentId), "Cannot take back: gift is unwrapped or not expired");
        _setStatus(presentId, PRESENT_TAKEN_BACK);
        totalPresentsTakenBack++;
        _transferAssets(presentId, msg.sender);
        emit TakeBack(presentId, msg.sender);
    }

    function takeBackTest(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) onlySender(presentId)
    {
        require(_canTakeBack(presentId), "Cannot take back: gift is unwrapped or not expired");
        _setStatus(presentId, PRESENT_TAKEN_BACK);
        totalPresentsTakenBack++;
        _transferAssets(presentId, msg.sender);
        emit TakeBackTest(presentId, msg.sender);
    }

    function _canTakeBack(bytes32 presentId) internal view returns (bool) {
        uint8 st = _getStatus(presentId);
        if (st == PRESENT_ACTIVE) return true;
        if (presents[presentId].expiryAt > 0 && block.timestamp > presents[presentId].expiryAt) return true;
        return false;
    }

    function _getStatus(bytes32 presentId) internal view returns (uint8) {
        PresentInfo storage p = presents[presentId];
        if (p.status == PRESENT_ACTIVE && _isExpired(presentId)) return PRESENT_EXPIRED;
        return p.status;
    }

    function _setStatus(bytes32 presentId, uint8 newStatus) internal {
        presents[presentId].status = newStatus;
    }

    function _getSender(bytes32 presentId) internal view returns (address) {
        return presents[presentId].sender;
    }

    function _getRecipients(bytes32 presentId) internal view returns (address[] memory) {
        return presents[presentId].recipients;
    }

    function _isExpired(bytes32 presentId) internal view returns (bool) {
        return (presents[presentId].expiryAt > 0 && block.timestamp > presents[presentId].expiryAt);
    }

    function getPresent(bytes32 presentId)
        external view
        returns (
            address sender,
            address[] memory recipients,
            Asset[] memory content,
            string memory title,
            string memory description,
            uint8 status,
            uint256 expiryAt
        )
    {
        PresentInfo storage p = presents[presentId];
        return (p.sender, p.recipients, p.content, p.title, p.description, _getStatus(presentId), p.expiryAt);
    }

    function getPresentContent(bytes32 presentId) external view returns (Asset[] memory) {
        return presents[presentId].content;
    }

    function getPresentStatus(bytes32 presentId) external view returns (uint8) {
        return _getStatus(presentId);
    }

    function generatePresentId(address[] calldata recipients, Asset[] calldata content)
        internal view returns (bytes32)
    {
        return keccak256(abi.encode(
            msg.sender,
            recipients,
            content,
            block.timestamp,
            block.prevrandao,
            address(this)
        ));
    }

    function _transferAssets(bytes32 presentId, address recipient) private {
        Asset[] memory assets = presents[presentId].content;
        uint256 assetsLength = assets.length;
        for (uint i = 0; i < assetsLength; i++) {
            if (assets[i].tokens == address(0)) {
                (bool success, ) = payable(recipient).call{value: assets[i].amounts}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(assets[i].tokens).safeTransfer(recipient, assets[i].amounts);
            }
        }
    }

    function setNFTContracts(address _wrappedNFT, address _unwrappedNFT) external onlyOwner {
        wrappedNFT = _wrappedNFT;
        unwrappedNFT = _unwrappedNFT;
    }

    function setTokenBlacklist(address token, bool blacklisted) external onlyOwner {
        require(token != address(0), "Cannot blacklist ETH");
        blacklistedTokens[token] = blacklisted;
        emit TokenBlacklisted(token, blacklisted);
    }

    function updateConfig(uint256 _maxAssetCount, uint256 _maxRecipientCount, uint256 _defaultExpiryPeriod)
        external onlyOwner
    {
        emit ConfigUpdated("maxAssetCount", maxAssetCount, _maxAssetCount);
        emit ConfigUpdated("maxRecipientCount", maxRecipientCount, _maxRecipientCount);
        emit ConfigUpdated("defaultExpiryPeriod", defaultExpiryPeriod, _defaultExpiryPeriod);
        maxAssetCount = _maxAssetCount;
        maxRecipientCount = _maxRecipientCount;
        defaultExpiryPeriod = _defaultExpiryPeriod;
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            require(amount <= address(this).balance, "Insufficient ETH balance");
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "ETH withdrawal failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
        emit EmergencyWithdraw(token, owner(), amount);
    }

    function forceExpirePresent(bytes32 presentId) external onlyOwner presentExists(presentId) {
        require(_getStatus(presentId) == PRESENT_ACTIVE, "Present not active");
        _setStatus(presentId, PRESENT_EXPIRED);
        totalPresentsExpired++;
        emit PresentExpired(presentId, _getSender(presentId));
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function isExpired(bytes32 presentId) public view returns (bool) { return _isExpired(presentId); }

    receive() external payable {}
}