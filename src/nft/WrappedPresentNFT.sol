// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

interface IPresentView {
    struct Asset { address tokens; uint256 amounts; }
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

contract WrappedPresentNFT is ERC721, Ownable {
    using Strings for uint256;

    address public presentContract;
    mapping(uint256 => bool) public minted;

    modifier onlyPresent() {
        require(msg.sender == presentContract, "Only Present");
        _;
    }

    constructor(string memory name_, string memory symbol_, address initialOwner) ERC721(name_, symbol_) Ownable(initialOwner) {}

    function setPresentContract(address present) external onlyOwner {
        presentContract = present;
    }

    function mint(address to, bytes32 presentId) external onlyPresent returns (uint256) {
        uint256 tokenId = uint256(presentId);
        require(!minted[tokenId], "Already minted");
        minted[tokenId] = true;
        _safeMint(to, tokenId);
        return tokenId;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        // 读取元信息
        (,, IPresentView.Asset[] memory content, string memory title, string memory desc,,) =
            IPresentView(presentContract).getPresent(bytes32(tokenId));

        string memory stateLabel = "WRAPPED";
        string memory name_ = string(abi.encodePacked("FarGift Wrapped #", tokenId.toString()));
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