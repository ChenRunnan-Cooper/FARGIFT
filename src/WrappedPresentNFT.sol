// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

//这个合约有被黑客攻击的风险，但现在我没时间弄安全或者加密措施
contract WrappedPresentNFT is ERC721, ERC721URIStorage, ERC721Enumerable {
    using Strings for uint256;
    
    address public presentContract;
    
    // NFT 元数据结构
    struct PresentMetadata {
        string title;
        string description;
        string imageType;  // "gift", "surprise", "business" 等
        uint256 value;     // 礼物价值（可选显示）
        address sender;    // 发送者
        uint256 createdAt; // 创建时间
    }
    
    // 存储每个 NFT 的元数据
    mapping(uint256 => PresentMetadata) public presentMetadata;
    
    constructor() ERC721("WrappedPresent", "WP") {
        presentContract = msg.sender;
    }
    
    function mint(
        address to, 
        uint256 tokenId,
        string memory title,
        string memory description,
        string memory imageType,
        uint256 value,
        address sender
    ) external {
        require(msg.sender == presentContract, "Only present contract can mint");
        
        // 存储元数据
        presentMetadata[tokenId] = PresentMetadata({
            title: title,
            description: description,
            imageType: imageType,
            value: value,
            sender: sender,
            createdAt: block.timestamp
        });
        
        _mint(to, tokenId);
        _setTokenURI(tokenId, generateTokenURI(tokenId));
    }
    
    // 生成动态 token URI
    function generateTokenURI(uint256 tokenId) internal view returns (string memory) {
        PresentMetadata memory metadata = presentMetadata[tokenId];
        
        // 生成 SVG 图片
        string memory svg = generateSVG(metadata);
        
        // 创建 JSON metadata
        string memory json = Base64.encode(
            abi.encodePacked(
                '{"name": "', metadata.title, '",',
                '"description": "', metadata.description, '",',
                '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
                '"attributes": [',
                    '{"trait_type": "Type", "value": "', metadata.imageType, '"},',
                    '{"trait_type": "Value", "value": ', metadata.value.toString(), '},',
                    '{"trait_type": "Sender", "value": "', Strings.toHexString(uint160(metadata.sender)), '"},',
                    '{"trait_type": "Created", "value": ', metadata.createdAt.toString(), '}',
                ']}'
            )
        );
        
        return string(abi.encodePacked("data:application/json;base64,", json));
    }
    
    // 生成 SVG 图片
    function generateSVG(PresentMetadata memory metadata) internal pure returns (string memory) {
        // 根据不同类型生成不同颜色和图案
        string memory primaryColor = getColorByType(metadata.imageType);
        string memory secondaryColor = getSecondaryColor(metadata.imageType);
        
        return string(
            abi.encodePacked(
                '<svg width="350" height="350" xmlns="http://www.w3.org/2000/svg">',
                '<defs>',
                    '<linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">',
                        '<stop offset="0%" stop-color="', primaryColor, '"/>',
                        '<stop offset="100%" stop-color="', secondaryColor, '"/>',
                    '</linearGradient>',
                '</defs>',
                
                // 背景
                '<rect width="350" height="350" fill="url(#grad)" rx="20"/>',
                
                // 礼物盒主体
                '<rect x="75" y="150" width="200" height="150" fill="white" stroke="', primaryColor, '" stroke-width="3" rx="10"/>',
                
                // 礼物盒盖子
                '<rect x="70" y="130" width="210" height="40" fill="', primaryColor, '" rx="8"/>',
                
                // 蝴蝶结
                '<polygon points="175,130 155,110 175,90 195,110" fill="', secondaryColor, '"/>',
                '<polygon points="175,130 195,110 215,130 195,150" fill="', secondaryColor, '"/>',
                '<circle cx="175" cy="130" r="8" fill="white"/>',
                
                // 装饰线条
                '<line x1="175" y1="150" x2="175" y2="300" stroke="', primaryColor, '" stroke-width="4"/>',
                '<line x1="75" y1="225" x2="275" y2="225" stroke="', primaryColor, '" stroke-width="2"/>',
                
                // 文字
                '<text x="175" y="40" text-anchor="middle" font-family="Arial" font-size="20" font-weight="bold" fill="white">',
                    bytes(metadata.title).length > 15 ? string(abi.encodePacked(substring(metadata.title, 0, 15), "...")) : metadata.title,
                '</text>',
                
                '<text x="175" y="70" text-anchor="middle" font-family="Arial" font-size="14" fill="white">',
                    'Value: $', metadata.value.toString(),
                '</text>',
                
                '<text x="175" y="330" text-anchor="middle" font-family="Arial" font-size="12" fill="white">',
                    'Wrapped Present #', uint256(uint160(metadata.sender)).toString(),
                '</text>',
                
                '</svg>'
            )
        );
    }
    
    // 根据类型获取主色调
    function getColorByType(string memory imageType) internal pure returns (string memory) {
        bytes32 typeHash = keccak256(abi.encodePacked(imageType));
        
        if (typeHash == keccak256("gift")) return "#FF6B6B";
        if (typeHash == keccak256("surprise")) return "#4ECDC4"; 
        if (typeHash == keccak256("business")) return "#45B7D1";
        if (typeHash == keccak256("birthday")) return "#FFA07A";
        if (typeHash == keccak256("holiday")) return "#98D8C8";
        
        return "#9013FE"; // 默认紫色
    }
    
    // 获取次要颜色
    function getSecondaryColor(string memory imageType) internal pure returns (string memory) {
        bytes32 typeHash = keccak256(abi.encodePacked(imageType));
        
        if (typeHash == keccak256("gift")) return "#FF8E53";
        if (typeHash == keccak256("surprise")) return "#6BCF7F";
        if (typeHash == keccak256("business")) return "#5B73C4";
        if (typeHash == keccak256("birthday")) return "#FFB347";
        if (typeHash == keccak256("holiday")) return "#B4E7CE";
        
        return "#7C4DFF"; // 默认深紫色
    }
    
    // 字符串截取工具函数
    function substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }
    
    // 新版本 OpenZeppelin 需要重写的函数
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }
    
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }
    
    // 重写必要的函数
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    
    // 获取 NFT 详细信息（用于前端显示）
    function getPresentInfo(uint256 tokenId) external view returns (PresentMetadata memory) {
        require(_ownerOf(tokenId) != address(0), "NFT does not exist");
        return presentMetadata[tokenId];
    }
    
    // 批量获取用户的 NFT - 使用 ERC721Enumerable 的功能优化性能
    function getUserNFTs(address user) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(user);
        uint256[] memory tokenIds = new uint256[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(user, i);
        }
        
        return tokenIds;
    }
}