# 本地资源准备规范

公开源码仓库不包含第三方游戏图片、音频、应用图标或原始 Scratch 归档。代码中的角色名称仅说明原型设计，不构成对任何第三方素材的许可。

自行准备原创或明确许可的资源后，放入以下位置。资源只在本地使用，已加入 Git 忽略规则。

| 路径 | 数量与命名 | 用途 |
| --- | --- | --- |
| `Resources/assets/peashooter/idle/` | `idle_01.png` … `idle_12.png` | 待机和移动 |
| `Resources/assets/peashooter/shoot/` | `shoot_01.png` … `shoot_11.png` | 蓄力和发射 |
| `Resources/assets/projectile/` | `projectile_01.png` | 弹丸 |
| `Resources/assets/impact/` | `impact_01.png` … `impact_04.png` | 命中飞溅 |
| `Resources/assets/zombies/walk/` | `zombie_01.png` … `zombie_16.png` | 担架角色行走 |
| `Resources/assets/sounds/` | `firepea.wav`、`splat.wav`、`pop.wav` | 发射与命中音效 |
| `Resources/AppIcon.icns` | 一个 macOS 图标文件 | 应用图标 |

角色帧采用透明 PNG，并保持统一画布和稳定中心。植物帧建议使用 512×512 像素；弹丸、飞溅和行走角色按代码中的显示尺寸准备足够的 Retina 分辨率。帧应与 `ExperienceLayout` 里的发射口偏移、朝向和碰撞点相适应，替换美术后需重新验证对齐。

可选彩蛋路径为 `Resources/assets/peashooter/easter_egg/helmet_01.png` … `helmet_03.png`，不属于首版主流程的必需资源。

公开源码仅附资源规范，不含自动下载第三方素材的脚本。完成本地准备后运行 `./Scripts/verify_project.sh`，再构建应用。只有自己拥有再分发权的资源才应进入后续公开发行包。
