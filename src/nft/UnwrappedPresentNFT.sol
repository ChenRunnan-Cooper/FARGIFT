// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
================================================================================
合约整体说明（UnwrappedPresentNFT.sol）
--------------------------------------------------------------------------------
一、合约目标
- 本合约是“已拆包（Unwrapped）礼物”的 ERC721 凭证合约。当用户在 Present 合约中成功 unwrap 礼物后，
  由 Present 合约通过本合约铸造一枚 NFT，表示该礼物已被拆开并领取。

二、核心设计
- tokenId = uint256(presentId)，与礼物 ID 一一对应（bytes32 → uint256）。
- 仅允许绑定的 Present 合约地址调用 mint（onlyPresent 修饰符）。
- 元数据采用链上 SVG + Base64 JSON 的 data URI 形式，便于前端直接渲染，无需外部存储依赖。
- 通过只读接口 IPresentViewU.getPresent 获取标题、描述与资产数量等展示信息。

三、工作流程
- 管理员调用 setPresentContract(address) 绑定 Present 合约地址；
- 当 Present.unwrap 成功后，由 Present 调用 mint(to, presentId)；
- 前端读取 tokenURI(tokenId) 获取 JSON（data:application/json;base64,...），再渲染 image（data:image/svg+xml;base64,...）。

四、安全与防重复
- onlyPresent 保护铸造入口；
- minted 映射防止同一 tokenId 被重复铸造。
================================================================================
*/

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // 管理员控制
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol"; // 标准 ERC721 实现
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol"; // uint256 → string 工具
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";   // Base64 编解码

// 只读接口：从 Present 合约读取礼物展示字段（最小化依赖）
interface IPresentViewU {
    struct Asset { address tokens; uint256 amounts; } // 展示使用
    function getPresent(bytes32 presentId)
        external
        view
        returns (
            address sender,
            address[] memory recipients,
            Asset[] memory content,
            string memory title,
            string memory description,
            uint8 status,
            uint256 expiryAt
        );
}

contract UnwrappedPresentNFT is ERC721, Ownable {
    using Strings for uint256;

    // 绑定的 Present 合约地址
    address public presentContract;
    // 防重复铸造：tokenId → 已铸造标记
    mapping(uint256 => bool) public minted;

    // 仅允许 Present 合约调用
    modifier onlyPresent() {
        require(msg.sender == presentContract, "Only Present");
        _;
    }

    // 构造函数：传入名称、符号与初始 owner
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
        uint256 tokenId = uint256(presentId);
        require(!minted[tokenId], "Already minted"); // 防止重复铸造
        minted[tokenId] = true;
        _safeMint(to, tokenId);                         // 安全铸造
        return tokenId;
    }

    // 生成元数据：返回 data:application/json;base64,...
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token"); // 确认存在
        // 读取展示信息：content.length/title/desc
        (,, IPresentViewU.Asset[] memory content, string memory title, string memory desc,,) =
            IPresentViewU(presentContract).getPresent(bytes32(tokenId));

        string memory stateLabel = "UNWRAPPED"; // 已拆包标签
        string memory name_ = string(abi.encodePacked("FarGift Unwrapped #", tokenId.toString()));
        string memory svg = _buildSVG(title, stateLabel);
        string memory image = string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svg))));

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

    // 组装 SVG：包含标题与状态标签；标题为空时给默认文案
    function _buildSVG(string memory title, string memory stateLabel) internal pure returns (string memory) {
        string memory t = bytes(title).length == 0 ? string(abi.encodePacked("FarGift ", stateLabel)) : title;
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">',
                '<defs><linearGradient id="g" x1="0" x2="1" y1="0" y2="1"><stop stop-color="#FDE68A"/><stop offset="1" stop-color="#FCA5A5"/></linearGradient></defs>',
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

    // 转义 XML 特殊字符
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

    // 转义 JSON 特殊字符
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