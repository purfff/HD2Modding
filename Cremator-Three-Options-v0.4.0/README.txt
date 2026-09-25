Cremator v0.4.0 — 三种互斥选项
适用：Steam build 25480438 / EXE 1.8.46015.0；需要 Bingus Shared Loader v16 / API 1。

A 原生火焰延程＋4/4
保留用户测试成功的原生延程方案。共享 Fire 17 普通/耐久直击3/3→4/4。
同时影响火焰炮塔和EXO-51的共享伤害；延程资源仅用于Cremator。

B 炮塔火焰射程＋3/3（平衡版）
保留之前低伤方案：Cremator使用炮塔/机甲火焰资源，伤害记录保持3/3。
没有额外平衡调整；此前近距离漏伤、部分环境黑方块等限制仍保留。

C 原生火焰延程＋3/3＋BurningHeavy（新增，待实测）
使用与A完全相同的原生延程粒子资源，但普通/耐久直击保持3/3。
保留原有Fire、另外两个已有状态和所有穿甲/冲击参数。
仅在共享伤害记录的第四个空状态槽追加BurningHeavy：当前编号32，附加值2。
数值2沿用当前游戏伤害记录6中的Fire＋BurningHeavy组合；这是状态附加量，不是每秒伤害。
不修改BurningHeavy本身的持续时间、持续伤害或目标易感性规则。
按用户授权，C也让火焰炮塔和EXO-51的共享直击附带BurningHeavy。
记录中同时存在Fire与BurningHeavy不代表所有目标都会接受或叠加两者；由原生状态逻辑决定，需实测。

安装/切换：完全退出游戏 → Import此ZIP替换旧条目 → A/B/C三选一 → Deploy → 重启。
同一GUID和Lua模块，不要同时启用旧版。切换必须重新Deploy并重启，以移除上个选项的状态或资源覆盖。
A/C有原生粒子归档，Lua构建锁不能阻止归档加载；游戏更新后先停用并核对版本。
前0.5米免伤/喷口前移没有加入。

日志：%LOCALAPPDATA%\CrematorBoost.log
A：APPLIED variant=native_range；B：APPLIED variant=range_only。
C：APPLIED variant=native_burning，damage_17=3/3_unchanged，BurningHeavy=32 value=2。
APPLIED只证明数据写入，不证明每个目标都触发重度燃烧。
C建议先验证射程与近距直喷，再比较停止喷射后的持续燃烧表现。
本包已做离线归档和Lua回放检查，未自动部署；C尚待用户实战验证。
