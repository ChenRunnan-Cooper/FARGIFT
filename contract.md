## Present.sol
### Events
``` solidity
event WrapPresent(bytes32 indexed presentId, address sender)
event UnwrapPresent(bytes32 indexed presentId, address taker)
event TakeBack(bytes32 indexed presentId, address sender)
```
要知道一个 event emit 出去在链上看是什么样子的，参考昨天索引的 transfer Log
### Types
``` solidity
struct Asset {
	address tokens
	amount  amounts
}
```
### States
``` solidity
mapping(bytes32 => Asset[]) contentOf
```
### Methods
1. `wrapPresent(address[] calldata recipients, Asset[] content)`：打包礼物
	- 礼物可以是 native ETH
	- 可以是任意 ERC20 token
	- 也可以是任意 ERC721 token （这个等其他所有逻辑都实现完在做）
	- we need to take custody of all these assets
	- 生成一个礼物ID，在状态中记录好ID及其对应的assets（这个ID是礼物内容 + sender address 等关键信息的 keccak hash）
	- 将礼物 wrap 之后会给 sender mint 一个 ERC721 token （wrapped present），记录礼物的内容（暂时不会 ERC721 的话，先 mint 一个 trivial 的 ERC721，我们之后再补充细节）
2. `unwrapPresent(bytes32 presentId)`
	- 拆开礼物，拿走其中的所有 assets
	- 成功之后 mint 一个 ERC721 token （unwrapped present）
	- 确保只有 sender 指定的 address 才能 unwrap 礼物
3. `takeBack(bytes32 presentId)`
	- sender 收回礼物

## Decorate.sol
- 将礼物装饰以 ERC1155 token 的形式出售