# PUBO 原生 iPhone：账号阶段

0.6.0/build55，以0.2.0/build22为基线，包含阶段一至四：私信/榜单/公告/游客/媒体/资料、群聊与集合、网盘、多账号及完整账号设置。保留四页导航，Pages/Play/Deck/网页主题与插件在系统浏览器打开。

新增账号认证材料受保护上传、隐私/通知/静音/屏蔽、邮箱密码/TOTP与会话、服务连接、数据任务/迁移。账号注销重新验证同一账号，密码及临时授权不持久保存，不确定结果禁止盲目重发。完整原生管理后台在下一整合阶段，不能套用后续证据。

具体范围见docs/PHASE4.md。自动化结果和IPA哈希见本构建交付目录DELIVERY.md；旧FEATURES/STATUS/H5_PARITY为build22历史。iOS17+，未签名iPhoneOS arm64 IPA，必须签名才能安装，不代表实机/TestFlight/上架完成。实体设备与真实推送仍待验。

构建：Xcode26.0.1、Swift6、XcodeGen；swift test；python3 -m unittest discover -s scripts -p 'test_*.py'；swift scripts/brand-assets.swift；xcodegen generate。GitHub Actions执行双尺寸UI、隔离真实API及Release，详见docs/BUILD.md。本阶段不改生产网站和任何服务配置，保留旧包与未提交内容。
