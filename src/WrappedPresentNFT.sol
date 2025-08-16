// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract WrappedPresentNFT is ERC721, ERC721URIStorage, ERC721Enumerable {
    using Strings for uint256;

    address public presentContract;
    address public deployer;
    
    // 存储每个NFT的礼物信息
    struct GiftInfo {
        string title;
        string message;
        uint256 ethValue;
        address creator;
    }
    
    mapping(uint256 => GiftInfo) public giftInfos;
    
    constructor(address _presentContract) ERC721("WrappedPresent", "WP") {
        presentContract = _presentContract;
        deployer = msg.sender;
    }

    // 添加设置函数，只有部署者能调用
    function setPresentContract(address _presentContract) external {
        require(msg.sender == deployer, "Only deployer can set");
        require(_presentContract != address(0), "Invalid address");
        presentContract = _presentContract;
    }

    // 修改mint函数，接收礼物的完整信息
    function mint(
        address to, 
        bytes32 presentId,
        string memory giftTitle,
        string memory giftMessage,
        uint256 ethValue,
        address creator
    ) external returns (uint256) {
        require(msg.sender == presentContract, "Only present contract can mint");
        
        uint256 tokenId = uint256(presentId);
        _mint(to, tokenId);
        
        // 存储礼物信息
        giftInfos[tokenId] = GiftInfo({
            title: giftTitle,
            message: giftMessage,
            ethValue: ethValue,
            creator: creator
        });
        
        string memory uri = generateTokenURI(tokenId, presentId);
        _setTokenURI(tokenId, uri);
        
        return tokenId;
    }

    // 获取礼物信息的公开函数
    function getGiftInfo(uint256 tokenId) external view returns (
        string memory title,
        string memory message,
        uint256 ethValue,
        address creator
    ) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        GiftInfo memory info = giftInfos[tokenId];
        return (info.title, info.message, info.ethValue, info.creator);
    }

    function generateTokenURI(
        uint256 tokenId,
        bytes32 presentId
    ) internal view returns (string memory) {
        GiftInfo memory giftInfo = giftInfos[tokenId];
        string memory svg = generateWrappedSVG(tokenId, presentId, giftInfo);
        
        // 生成属性数组
        string memory attributes = string(
            abi.encodePacked(
                '[',
                    '{"trait_type": "Present ID", "value": "', uint256(presentId).toString(), '"},',
                    '{"trait_type": "Type", "value": "Wrapped"},',
                    '{"trait_type": "ETH Value", "value": "', (giftInfo.ethValue / 1e15).toString(), '"},',
                    '{"trait_type": "Creator", "value": "', Strings.toHexString(uint160(giftInfo.creator), 20), '"}',
                ']'
            )
        );
        
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "', giftInfo.title, '",',
                        '"description": "', giftInfo.message, '",',
                        '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
                        '"attributes": ', attributes,
                        '}'
                    )
                )
            )
        );
        
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function generateWrappedSVG(
        uint256 tokenId, 
        bytes32 presentId,
        GiftInfo memory giftInfo
    ) internal pure returns (string memory) {
        // 根据ETH价值调整颜色
        string memory boxColor = giftInfo.ethValue >= 1e18 ? "#ff6b6b" : giftInfo.ethValue >= 1e16 ? "#ffa500" : "#ff69b4";
        string memory ribbonColor = "#ffd93d";
        
        // 截断长标题用于显示
        string memory displayTitle = bytes(giftInfo.title).length > 20 ? 
            string(abi.encodePacked(substring(giftInfo.title, 0, 17), "...")) : 
            giftInfo.title;
            
        return string(
            abi.encodePacked(
                '<svg width="400" height="400" xmlns="http://www.w3.org/2000/svg">',
                '<rect width="400" height="400" fill="#f8f9fa"/>',
                '<rect x="50" y="80" width="300" height="240" fill="', boxColor, '" rx="10"/>',
                '<rect x="40" y="70" width="320" height="20" fill="', ribbonColor, '"/>',
                '<rect x="190" y="60" width="20" height="280" fill="', ribbonColor, '"/>',
                '<circle cx="200" cy="80" r="25" fill="', ribbonColor, '"/>',
                '<text x="200" y="190" text-anchor="middle" font-family="Arial" font-size="18" fill="white" font-weight="bold">',
                displayTitle,
                '</text>',
                '<text x="200" y="220" text-anchor="middle" font-family="Arial" font-size="14" fill="white">',
                'Value: ', (giftInfo.ethValue / 1e15).toString(), ' mETH',
                '</text>',
                '<text x="200" y="240" text-anchor="middle" font-family="Arial" font-size="14" fill="white">',
                'Token #', tokenId.toString(),
                '</text>',
                '<text x="200" y="260" text-anchor="middle" font-family="Arial" font-size="12" fill="white">',
                'Click to unwrap!',
                '</text>',
                '</svg>'
            )
        );
    }
    
    // 辅助函数：字符串截取
    function substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    // 重写tokenURI函数以支持动态元数据
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        // 如果没有设置URI，则生成动态URI
        string memory _tokenURI = super.tokenURI(tokenId);
        if (bytes(_tokenURI).length == 0) {
            return generateTokenURI(tokenId, bytes32(tokenId));
        }
        return _tokenURI;
    }

    // Override functions
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}