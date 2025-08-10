# Handover – Miniapp / Farcaster 组接入说明（测试网）

目标：给你们一份“拿来就能用”的接入手册，包含 1）在哪里拿 ABI 与合约地址，2）如何在链上拿到样例日志（wrap/unwrap/takeBack），3）如何解码与渲染礼物详情。

---

## 零配置信息（直接复制使用）
- 链：Arbitrum Sepolia（chainId 421614）
- Present 合约地址（统一使用此地址聚合样例与订阅）
  - 0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db
- 一键导出（终端粘贴）：
  ```bash
  export VITE_CHAIN_ID=421614
  export VITE_PRESENT_ADDRESS=0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db
  # 任选一个稳定的 RPC：
  export VITE_RPC_HTTP="https://arb-sepolia.g.alchemy.com/v2/<KEY>"
  ```

---

## 一、你们需要哪些最小信息
- 链：Arbitrum Sepolia（chainId 421614）
- 合约地址：统一使用同一个 `Present` 地址（便于订阅聚合）
  - 0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db
- ABI（“纯 ABI 数组”，可直接被 SDK 使用）
  - `abi/raw/Present.abi.json`
  - 如需 NFT 的 `tokenURI` 展示：
    - `abi/raw/WrappedPresentNFT.abi.json`
    - `abi/raw/UnwrappedPresentNFT.abi.json`

说明：ABI 只定义“事件/函数的形状”，不包含历史日志。历史日志存于链上，按合约地址 + 事件名直接订阅/查询即可。

---

## 二、有哪些事件（你们应关注）
- 生产事件（推荐）：
  - `WrapPresent(bytes32 indexed presentId, address sender)`
  - `UnwrapPresent(bytes32 indexed presentId, address taker)`
  - `TakeBack(bytes32 indexed presentId, address sender)`
- 测试事件（若使用 *Test 入口）：
  - `WrapPresentTest(bytes32 indexed presentId, address sender)`
  - `UnwrapPresentTest(bytes32 indexed presentId, address taker)`
  - `TakeBackTest(bytes32 indexed presentId, address sender)`

你们可以同时订阅生产与测试事件，或只订一种。presentId 一律是 indexed，可按 presentId 过滤。

---

## 三、如何获取“样例数据”（我们已在测试网生成）
我们已在测试网上，向同一个 `Present` 地址追加了多组样例：
- A: wrap → unwrap（定向）
- B: wrap → takeBack（定向）
- C: 公开礼物（recipients=[]）→ unwrap
- D: wrap 后保持 ACTIVE
- ERC20：先 approve，再 wrapPresentTest（带 title/description）

你们可以：
- 用区块浏览器，搜索 `Present` 地址，查看 Events 页签；
- 或用 RPC/SDK（见下文示例）拉取：WrapPresent / UnwrapPresent / TakeBack（以及 *Test 变体）。

我们会附带几个示例 presentId（便于你们对照回放），但以链上数据为准。

---

## 四、如何订阅/查询事件（viem 示例）

1) 初始化
```ts
import { createPublicClient, http } from 'viem';
import { arbitrumSepolia } from 'viem/chains';
import presentAbi from '../abi/raw/Present.abi.json';

const client = createPublicClient({ chain: arbitrumSepolia, transport: http(process.env.VITE_RPC_HTTP) });
const PRESENT = '0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db';
```

2) 监听实时事件（HTTP 轮询）
```ts
client.watchContractEvent({
  address: PRESENT,
  abi: presentAbi,
  eventName: 'WrapPresent',
  onLogs: logs => {
    for (const l of logs) {
      const { presentId, sender } = l.args;
      // 存入你的本地状态，后面用 presentId 拉详情
    }
  }
});

// 也可以同时订阅 UnwrapPresent、TakeBack 以及 *Test 事件
```

3) 查询历史日志（getLogs）
```ts
const pastWraps = await client.getLogs({
  address: PRESENT,
  event: { name: 'WrapPresent', type: 'event', inputs: presentAbi.find(e => e.name==='WrapPresent' && e.type==='event').inputs },
  fromBlock: 0n,
  toBlock: 'latest'
});
```

---

## 五、如何读取礼物详情（只读函数）

`getPresent(presentId)` 一次返回：sender、recipients、content、title、description、status、expiryAt。

```ts
import { getContract } from 'viem';
const present = getContract({ address: PRESENT, abi: presentAbi, client });

// presentId: bytes32（从事件里拿到）；可以是 '0x...' 字符串
const [sender, recipients, content, title, desc, status, expiryAt] = await present.read.getPresent([presentId]);

// content: { tokens: address, amounts: uint256 }[]
// tokens == 0x0000...0000 表示 ETH；否则为 ERC20 地址
```

若只需资产或状态，也可使用：
- `getPresentContent(bytes32)`
- `getPresentStatus(bytes32)`

---

## 六、NFT 展示（可选）

两个 NFT 的 tokenId = uint256(presentId)。如需渲染：
```ts
import wrappedAbi from '../abi/raw/WrappedPresentNFT.abi.json';
const wrapped = getContract({ address: '0x<WrappedNFT>', abi: wrappedAbi, client });
const tokenURI = await wrapped.read.tokenURI([BigInt(presentId)]);
// tokenURI 是 data:application/json;base64,... → 解码后有 image(svg base64)、attributes
```

---

## 七、常见问题（你们可能会问）
- 我们需要你们导出“日志文件”吗？
  - 不需要。日志在链上。你们只需要链、合约地址和 ABI，就能自行拉取/订阅。
- ABI 里有“历史日志”吗？
  - 没有。ABI 只有事件/函数定义，历史日志全部在链上。
- 为什么有 WrapPresent 和 WrapPresentTest 两种？
  - 逻辑一致，后者带 title/description（便于测试渲染），订阅任选或两者都订。
- presentId 哪里来？
  - 事件 args 里（indexed）。你们维护一个 presentId → 详情 的状态映射即可。

---

## 八、验证你们接入是否成功（操作清单）
- [ ] 能用 getLogs 拉到至少一条 WrapPresent（或 WrapPresentTest）
- [ ] 能从事件 args 解析出 presentId
- [ ] 能调用 getPresent(presentId) 拿到完整详情（sender/recipients/content/title/desc/status/expiryAt）
- [ ] 能监听 UnwrapPresent/TakeBack（或对应 *Test），状态能实时更新
- [ ] （可选）能按 tokenId=uint256(presentId) 读取 Wrapped/Unwrapped tokenURI 并渲染

---

## 九、Cast 快捷核对（命令行）
```bash
# 查看某笔交易的事件（提取 presentId）
TX=0x<txHash>
cast receipt $TX --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL"

# 读取礼物聚合信息
cast call 0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db \
  "getPresent(bytes32)((address,address[],(address,uint256)[],string,string,uint8,uint256))" \
  0x<PRESENT_ID> \
  --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL"
```

---

## 十、附：如果需要自己再追加样例（由我们或你们跑均可）
- ETH 样例（四组）：`script/GenerateSamplesOnExisting.s.sol`
- 仅 wrap ETH 一次：`script/WrapOnly.s.sol`
- ERC20 样例（自动部署 MockERC20 → mint → approve → wrapPresentTest）：`script/WrapWithERC20.s.sol`

运行方式详见 README“在测试网上批量生成样例数据”。 