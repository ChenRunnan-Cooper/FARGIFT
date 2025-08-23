// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

// --- 新增：Present 合约的只读接口 ---
interface IPresentView {
    struct Asset {
        address tokens;
        uint256 amounts;
    }
    enum DistributionType {
        FIRST_COME_FIRST_SERVED,
        LIMITED_QUANTITY_EQUAL_SPLIT,
        WHITELIST_EQUAL_SPLIT,
        LIMITED_QUANTITY_RANDOM_SPLIT
    }
    function getPresent(bytes32 presentId)
        external view
        returns (
            address sender,
            string memory title,
            string memory description,
            uint8 status,
            uint256 expiryAt,
            DistributionType distType,
            uint256 claimLimit,
            uint256 claimedCount
        );
    function getPresentContent(bytes32 presentId) external view returns (Asset[] memory);
}


contract WrappedPresentNFT is ERC721, ERC721URIStorage, ERC721Enumerable {
    using Strings for uint256;

    address public presentContract;
    address public deployer;
    
    // --- 移除 GiftInfo 结构体和 mapping ---
    
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

    // --- 简化 mint 函数，以匹配 Present.sol 的调用 ---
    function mint(
        address to, 
        bytes32 presentId
    ) external returns (uint256) {
        require(msg.sender == presentContract, "Only present contract can mint");
        
        uint256 tokenId = uint256(presentId);
        _mint(to, tokenId);
        
        // 不再存储礼物信息或设置 tokenURI
        return tokenId;
    }

    // --- 移除 getGiftInfo 函数 ---

    // --- 修改 generateTokenURI 以实时获取数据 ---
    function generateTokenURI(
        uint256 tokenId
    ) internal view returns (string memory) {
        IPresentView present = IPresentView(presentContract);
        bytes32 presentId = bytes32(tokenId);

        // 从 Present.sol 实时获取数据
        (address creator, string memory title, string memory description,,,,,) = present.getPresent(presentId);
        IPresentView.Asset[] memory assets = present.getPresentContent(presentId);
        
        // 计算 ETH 总价值
        uint256 ethValue = 0;
        for (uint i = 0; i < assets.length; i++) {
            if (assets[i].tokens == address(0)) {
                ethValue += assets[i].amounts;
            }
        }
        
        string memory svg = generateWrappedSVG(tokenId, title, ethValue);
        
        string memory attributes = string(
            abi.encodePacked(
                '[',
                    '{"trait_type": "Present ID", "value": "', tokenId.toString(), '"},',
                    '{"trait_type": "Type", "value": "Wrapped"},',
                    '{"trait_type": "ETH Value", "value": "', (ethValue / 1e15).toString(), ' mETH"},', // 修改单位
                    '{"trait_type": "Creator", "value": "', Strings.toHexString(uint160(creator), 20), '"}',
                ']'
            )
        );
        
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "', title, '",',
                        '"description": "', description, '",',
                        '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
                        '"attributes": ', attributes,
                        '}'
                    )
                )
            )
        );
        
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    // --- 修改 generateWrappedSVG 的参数 ---
    function generateWrappedSVG(
        uint256 tokenId, 
        string memory giftTitle,
        uint256 ethValue
    ) internal pure returns (string memory) {
        string memory boxColor = ethValue >= 1e18 ? "#ff6b6b" : ethValue >= 1e16 ? "#ffa500" : "#ff69b4";
        string memory ribbonColor = "#ffd93d";
        
        string memory displayTitle = bytes(giftTitle).length > 20 ? 
            string(abi.encodePacked(substring(giftTitle, 0, 17), "...")) : 
            giftTitle;
            
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
                'Value: ', (ethValue / 1e15).toString(), ' mETH',
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
        return generateTokenURI(tokenId);
    }

    // --- 修复 OpenZeppelin v5.0 的 override 要求 ---
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