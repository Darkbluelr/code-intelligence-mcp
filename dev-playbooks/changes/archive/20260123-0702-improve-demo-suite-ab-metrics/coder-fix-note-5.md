# coder-fix-note-5

## 修复内容
- 恢复 `docs/demos/README.md`，补齐公开归档约束、run-id 命名规范、示例结构、复制流程、自检清单，并新增可选敏感信息扫描建议。

## 阻断原因
- `code-review-4.md` 指出 `docs/demos/README.md` 缺失导致 `demo/DEMO-GUIDE.md` 与 `dev-playbooks/docs/长期可复用演示方案.md` 的引用失效，公开归档约束无法被验证。

## 最小验证
- `test -f docs/demos/README.md`
