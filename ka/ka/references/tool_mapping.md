# Synopsys EDA 工具名映射

当用户提到以下关键词时，映射到对应的 `--tool-name` 参数值。

## 仿真 & 调试

| 用户说法 | --tool-name |
|---------|-------------|
| VCS、vcs、仿真编译、elaboration error、simv | `vcs` |
| Verdi、verdi、波形、nWave、调试波形 | `verdi` |
| DVE、dve | `dve` |

## 综合

| 用户说法 | --tool-name |
|---------|-------------|
| DC、Design Compiler、design_vision、综合、compile_ultra | `dc` |
| FC、Fusion Compiler、fc_shell、融合编译器 | `fc` |

## 时序分析

| 用户说法 | --tool-name |
|---------|-------------|
| PT、PrimeTime、pt_shell、STA、时序分析、report_timing | `pt` |

## 物理验证

| 用户说法 | --tool-name |
|---------|-------------|
| ICV、IC Validator、物理验证、DRC、LVS | `icv` |

## 形式验证

| 用户说法 | --tool-name |
|---------|-------------|
| Formality、formality、等价性检查 | `formality` |

## 版本映射

| 年份标识 | --tool-version 示例 |
|---------|---------------------|
| 2026 最新版 | `Y-2026.03` |
| 2025 版 | `X-2025.06` |

> 未明确指定版本时，默认使用 `Y-2026.03`。
