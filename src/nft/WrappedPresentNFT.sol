// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
================================================================================
合约整体说明（WrappedPresentNFT.sol）
--------------------------------------------------------------------------------
一、合约目标
- 本合约是“已打包（Wrapped）礼物”的 ERC721 凭证合约。当用户在 Present 合约中成功 wrap 礼物后，
  由 Present 合约通过本合约铸造一枚 NFT，表示该礼物处于已打包状态。

二、核心设计
- tokenId = uint256(presentId)，一一对应礼物 ID（bytes32 → uint256 强转）。
- 仅允许被授权的 Present 合约地址调用 mint（onlyPresent 修饰符）。
- 元数据采用链上方式构建（SVG → Base64 → data URI JSON），无需外部存储依赖。
- 在构建元数据时通过最小只读接口 IPresentView.getPresent 读取展示所需字段。

三、工作流程
- 管理员部署后，先调用 setPresentContract(address) 绑定 Present 合约地址；
- 当 Present.wrap 成功后，Present 调用 mint(to, presentId)；
- 前端读取 tokenURI(tokenId) 获取 data:application/json;base64,...，解析出图片（data:image/svg+xml;base64,...）和属性。

四、安全与防重复
- onlyPresent：限制只有绑定的 Present 合约才能铸造；
- minted 映射：防止同一个 tokenId 被重复铸造。
================================================================================
*/

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // 管理员控制
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol"; // 标准 ERC721 实现
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol"; // 字符串工具（uint256 → string）
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";   // Base64 编解码

// 只读接口：从 Present 合约读取礼物展示所需字段（降低耦合，只声明所需）
interface IPresentView {
    struct Asset { address tokens; uint256 amounts; } // 展示使用：资产条目（地址+数量）
    function getPresent(bytes32 presentId)
        external
        view
        returns (
            address sender,               // 送礼人
            address[] memory recipients,  // 接收者数组
            Asset[] memory content,       // 资产列表（仅读取长度用于属性）
            string memory title,          // 标题（用于 SVG 文本）
            string memory description,    // 描述（用于 JSON description）
            uint8 status,                 // 当前状态（展示可选）
            uint256 expiryAt              // 过期时间（展示可选）
        );
}

contract WrappedPresentNFT is ERC721, Ownable {
    using Strings for uint256; // 为 uint256 增加 toString 扩展

    // 绑定的 Present 合约地址；仅该地址可调用 mint
    address public presentContract;

    // 防重复铸造：tokenId → 是否已铸造
    mapping(uint256 => bool) public minted;

    // 仅允许 Present 合约调用的修饰符
    modifier onlyPresent() {
        require(msg.sender == presentContract, "Only Present");
        _;
    }

    // 构造函数：传入名称与符号，以及初始 owner
    constructor(string memory name_, string memory symbol_, address initialOwner)
        ERC721(name_, symbol_)
        Ownable(initialOwner)
    {}

    // 管理员设置/更新 Present 合约地址
    function setPresentContract(address present) external onlyOwner {
        presentContract = present;
    }

    // 铸造入口：仅 Present 合约可调用；tokenId 基于 presentId 强转
    function mint(address to, bytes32 presentId) external onlyPresent returns (uint256) {
        uint256 tokenId = uint256(presentId);          // bytes32 → uint256 作为 NFT 的 tokenId
        require(!minted[tokenId], "Already minted"); // 防重复铸造
        minted[tokenId] = true;                        // 标记已铸
        _safeMint(to, tokenId);                        // 安全铸造（检查接收方是否能接收 ERC721）
        return tokenId;
    }

    // 生成元数据：返回 data:application/json;base64,...
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token"); // 确保 token 存在
        // 读取展示所需信息（仅使用 content.length/title/desc）
        (,, IPresentView.Asset[] memory content, string memory title, string memory desc,,) =
            IPresentView(presentContract).getPresent(bytes32(tokenId));

        // 固定状态标签（本合约表示 WRAPPED）
        string memory stateLabel = "WRAPPED";
        // 名称包含 tokenId
        string memory name_ = string(abi.encodePacked("FarGift Wrapped #", tokenId.toString()));
        // 构建 SVG 并编码为 data:image/svg+xml;base64,...
        string memory svg = _buildSVG(title, stateLabel);
        string memory image = string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svg))));

        // 构建 JSON 并 Base64 编码；包括 name/description/image/attributes
        bytes memory json = abi.encodePacked(
            '{',
                '"name":"', name_, '",',
                '"description":"', _escapeJSON(desc), '",',
                '"image":"', image, '",',
                '"attributes":[',
                    '{"trait_type":"state","value":"', stateLabel, '"},',
                    '{"trait_type":"assets","value":"', Strings.toString(content.length), '"}',
                ']',
            '}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    // 组装 SVG：标题与状态标签；title 为空时提供默认文案
    function _buildSVG(string memory title, string memory stateLabel) internal pure returns (string memory) {
        string memory t = bytes(title).length == 0 ? string(abi.encodePacked("FarGift ", stateLabel)) : title;
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">',
                '<defs><linearGradient id="g" x1="0" x2="1" y1="0" y2="1"><stop stop-color="#6EE7F9"/><stop offset="1" stop-color="#A78BFA"/></linearGradient></defs>',
                '<rect width="512" height="512" fill="url(#g)"/>',
                '<text x="50%" y="45%" dominant-baseline="middle" text-anchor="middle" font-size="28" font-family="sans-serif" fill="#111">',
                _escapeXML(t),
                '</text>',
                '<text x="50%" y="58%" dominant-baseline="middle" text-anchor="middle" font-size="18" font-family="monospace" fill="#222">',
                stateLabel,
                '</text>',
                '</svg>'
            )
        );
    }

    // 转义 XML 特殊字符，避免 SVG 文本因特殊字符导致解析问题
    function _escapeXML(string memory input) internal pure returns (string memory) {
        bytes memory s = bytes(input);
        bytes memory out;
        for (uint i = 0; i < s.length; i++) {
            bytes1 c = s[i];
            if (c == '"') out = abi.encodePacked(out, "&quot;");
            else if (c == "'") out = abi.encodePacked(out, "&apos;");
            else if (c == "<") out = abi.encodePacked(out, "&lt;");
            else if (c == ">") out = abi.encodePacked(out, "&gt;");
            else if (c == "&") out = abi.encodePacked(out, "&amp;");
            else out = abi.encodePacked(out, c);
        }
        return string(out);
    }

    // 转义 JSON 字符，确保内嵌字符串合法
    function _escapeJSON(string memory input) internal pure returns (string memory) {
        bytes memory s = bytes(input);
        bytes memory out;
        for (uint i = 0; i < s.length; i++) {
            bytes1 c = s[i];
            if (c == '"') out = abi.encodePacked(out, '\\"');
            else if (c == "\\") out = abi.encodePacked(out, "\\\\");
            else if (c == "\n") out = abi.encodePacked(out, "\\n");
            else out = abi.encodePacked(out, c);
        }
        return string(out);
    }
} 