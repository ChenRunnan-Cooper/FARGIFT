// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

// Present 合约的只读接口，完全匹配主合约
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

contract WrappedPresentNFT is ERC721, ERC721URIStorage, ERC721Enumerable, Ownable {
    using Strings for uint256;

    address public presentContract;
    
    // 新增事件
    event PresentNFTMinted(address indexed to, bytes32 indexed presentId, uint256 indexed tokenId);
    event PresentContractUpdated(address indexed oldContract, address indexed newContract);
    event TokenURIRequested(uint256 indexed tokenId);
    
    constructor(address _presentContract) ERC721("WrappedPresent", "WP") Ownable(msg.sender) {
        require(_presentContract != address(0), "Invalid present contract address");
        presentContract = _presentContract;
        emit PresentContractUpdated(address(0), _presentContract);
    }

    // 设置Present合约地址，只有所有者能调用
    function setPresentContract(address _presentContract) external onlyOwner {
        require(_presentContract != address(0), "Invalid address");
        address oldContract = presentContract;
        presentContract = _presentContract;
        emit PresentContractUpdated(oldContract, _presentContract);
    }

    // 实现主合约需要的IPresentNFT接口：mint函数
    // 完全匹配主合约调用：IPresentNFT(wrappedNFT).mint(msg.sender, presentId);
    function mint(address to, bytes32 presentId) external returns (uint256) {
        require(msg.sender == presentContract, "Only present contract can mint");
        require(to != address(0), "Cannot mint to zero address");
        
        uint256 tokenId = uint256(presentId);
        
        // 检查tokenId是否已存在
        require(_ownerOf(tokenId) == address(0), "Token already exists");
        
        _mint(to, tokenId);
        
        emit PresentNFTMinted(to, presentId, tokenId);
        
        return tokenId;
    }

    // 动态生成tokenURI，实时从Present合约获取数据
    function generateTokenURI(uint256 tokenId) internal view returns (string memory) {
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
        
        string memory attributes = string(
            abi.encodePacked(
                '[',
                    '{"trait_type": "Present ID", "value": "', tokenId.toString(), '"},',
                    '{"trait_type": "Type", "value": "Wrapped"},',
                    '{"trait_type": "ETH Value", "value": "', (ethValue / 1e15).toString(), ' mETH"},',
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
                        '"image": "https://ipfs.io/ipfs/QmZcGoCRZBzbdM6WMudgXqmtzQycNpBJjTegafrvVEPRLL",',
                        '"attributes": ', attributes,
                        '}'
                    )
                )
            )
        );
        
        return string(abi.encodePacked("data:application/json;base64,", json));
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

    // 修复 OpenZeppelin v5.0 的 override 要求
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