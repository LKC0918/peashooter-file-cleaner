# 运行资源清单与替换规范

本版本包含发布者提供并确认可再分发的以下必要运行资源；不包含原始 Scratch 归档或私人授权资料。第三方许可边界见根目录 `THIRD_PARTY_NOTICES.md`。代码中的角色名称不构成对第三方素材的额外许可。

以下 47 个图像/音频文件与一个 ICNS 应用图标均经过元数据清理。需要替换为原创或其他明确许可的资源时，请保持以下路径与帧数：

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

头盔彩蛋不属于此版本的必需资源，未纳入公开资源白名单或安装包。

`prepare_release_assets.rb` 仅从你明确指定的已有授权项目中提取白名单运行资源：PNG 删除描述性块；WAV 删除文本、作者与其他附带信息；ICNS 重新组装并删除元数据。它不下载原始素材、不修改原始目录。处理后运行 `ruby Scripts/check_public_snapshot.rb` 和 `./Scripts/verify_project.sh`。只有自己拥有再分发权的资源才应进入后续公开发行包。
