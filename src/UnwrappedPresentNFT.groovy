// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

//这个合约有被黑客攻击的风险，但现在我没时间弄安全或者加密措施
contract UnwrappedPresentNFT is ERC721, ERC721URIStorage {
    using Strings for uint256;
    
    address public presentContract;
    
    // NFT 元数据结构
    struct UnwrappedMetadata {
        string title;
        string description;
        string imageType;  // "gift", "surprise", "business" 等
        uint256 value;     // 礼物价值（已拆开，显示原始价值）
        address sender;    // 原发送者
        address opener;    // 拆包者
        uint256 unwrappedAt; // 拆包时间
    }
    
    // 存储每个 NFT 的元数据
    mapping(uint256 => UnwrappedMetadata) public unwrappedMetadata;
    
    constructor() ERC721("UnwrappedPresent", "UP") {
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
        unwrappedMetadata[tokenId] = UnwrappedMetadata({
            title: string(abi.encodePacked("Opened: ", title)),  // 添加 "Opened:" 前缀
            description: string(abi.encodePacked("Unwrapped gift: ", description)),
            imageType: "unwrapped",  // 统一设为已拆开类型
            value: value,
            sender: sender,    // 原发送者
            opener: to,        // 拆包者
            unwrappedAt: block.timestamp
        });
        
        _mint(to, tokenId);
        _setTokenURI(tokenId, generateTokenURI(tokenId));
    }
    
    // 生成动态 token URI
    function generateTokenURI(uint256 tokenId) internal view returns (string memory) {
        UnwrappedMetadata memory metadata = unwrappedMetadata[tokenId];
        
        // 生成 SVG 图片
        string memory svg = generateSVG(metadata);
        
        // 创建 JSON metadata
        string memory json = Base64.encode(
            abi.encodePacked(
                '{"name": "', metadata.title, '",',
                '"description": "', metadata.description, '",',
                '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
                '"attributes": [',
                    '{"trait_type": "Status", "value": "Unwrapped"},',
                    '{"trait_type": "Original Value", "value": ', metadata.value.toString(), '},',
                    '{"trait_type": "Original Sender", "value": "', Strings.toHexString(uint160(metadata.sender)), '"},',
                    '{"trait_type": "Opened By", "value": "', Strings.toHexString(uint160(metadata.opener)), '"},',
                    '{"trait_type": "Unwrapped At", "value": ', metadata.unwrappedAt.toString(), '}',
                ']}'
            )
        );
        
        return string(abi.encodePacked("data:application/json;base64,", json));
    }
    
    // 生成 SVG 图片（已拆开的礼物样式）
    function generateSVG(UnwrappedMetadata memory metadata) internal pure returns (string memory) {
        // 已拆开礼物使用特殊的颜色方案
        string memory primaryColor = "#8E8E8E";    // 灰色调表示已拆开
        string memory secondaryColor = "#B8B8B8";  // 浅灰色
        string memory accentColor = "#FFD700";     // 金色作为强调色
        
        return string(
            abi.encodePacked(
                '<svg width="350" height="350" xmlns="http://www.w3.org/2000/svg">',
                '<defs>',
                    '<linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">',
                        '<stop offset="0%" stop-color="', primaryColor, '"/>',
                        '<stop offset="100%" stop-color="', secondaryColor, '"/>',
                    '</linearGradient>',
                    '<pattern id="openPattern" patternUnits="userSpaceOnUse" width="20" height="20">',
                        '<rect width="20" height="20" fill="none" stroke="', accentColor, '" stroke-width="1" opacity="0.3"/>',
                    '</pattern>',
                '</defs>',
                
                // 背景
                '<rect width="350" height="350" fill="url(#grad)" rx="20"/>',
                '<rect width="350" height="350" fill="url(#openPattern)" rx="20"/>',
                
                // 打开的礼物盒（散乱的样子）
                '<rect x="65" y="160" width="220" height="140" fill="white" stroke="', primaryColor, '" stroke-width="3" rx="10" transform="rotate(2 175 230)"/>',
                
                // 掀开的盖子
                '<rect x="60" y="120" width="230" height="30" fill="', primaryColor, '" rx="8" transform="rotate(-15 175 135)"/>',
                
                // 散落的蝴蝶结
                '<polygon points="140,100 125,85 140,70 155,85" fill="', accentColor, '" transform="rotate(-30 140 85)"/>',
                '<polygon points="210,110 195,95 210,80 225,95" fill="', accentColor, '" transform="rotate(45 210 95)"/>',
                '<circle cx="140" cy="85" r="6" fill="white"/>',
                '<circle cx="210" cy="95" r="6" fill="white"/>',
                
                // 装饰线条（表示打开状态）
                '<line x1="175" y1="160" x2="175" y2="300" stroke="', primaryColor, '" stroke-width="2" stroke-dasharray="5,5"/>',
                '<line x1="65" y1="230" x2="285" y2="230" stroke="', primaryColor, '" stroke-width="2" stroke-dasharray="5,5"/>',
                
                // 文字
                '<text x="175" y="35" text-anchor="middle" font-family="Arial" font-size="18" font-weight="bold" fill="white">',
                    '✓ OPENED',
                '</text>',
                
                '<text x="175" y="60" text-anchor="middle" font-family="Arial" font-size="14" fill="white">',
                    'Original Value: $', metadata.value.toString(),
                '</text>',
                
                '<text x="175" y="320" text-anchor="middle" font-family="Arial" font-size="10" fill="white">',
                    'Unwrapped by: ', Strings.toHexString(uint160(metadata.opener)),
                '</text>',
                
                '<text x="175" y="335" text-anchor="middle" font-family="Arial" font-size="10" fill="white">',
                    'Unwrapped Present #', uint256(uint160(metadata.sender)).toString(),
                '</text>',
                
                '</svg>'
            )
        );
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
    
    // 重写必要的函数
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }
    
    // 获取 NFT 详细信息（用于前端显示）
    function getUnwrappedInfo(uint256 tokenId) external view returns (UnwrappedMetadata memory) {
        require(_exists(tokenId), "NFT does not exist");
        return unwrappedMetadata[tokenId];
    }
    
    // 批量获取用户的 NFT
    function getUserNFTs(address user) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(user);
        uint256[] memory tokenIds = new uint256[](balance);
        uint256 currentIndex = 0;
        
        // 性能极差的代码
        for (uint256 i = 1; i <= totalSupply() && currentIndex < balance; i++) {
            if (_exists(i) && ownerOf(i) == user) {
                tokenIds[currentIndex] = i;
                currentIndex++;
            }
        }
        
        return tokenIds;
    }
    
    
}