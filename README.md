# workflow-git
## a git workflow tool
#### git分支合并与管理工具
========================
#### 命令说明
##### new: 从主分支/基准分支拉出新的开发分支
##### init: 创建用于缓存已合并分支的build-cache分支和用于整合所有代码的develop分支
##### ci: 将本分支的代码合入develop分支，并同时整合其他已合并分支的最新代码；如有自己分支的冲突，直接解决并强制提交
##### init-sub: submodule的init操作
##### ci-sub: submodule的ci操作
##### sync-dev-sub: 同步submodule
========================
##### 可通过在init和ci时指定prefix来区分不同环境/不同版本的dev分支
##### 如设置prefix为preview将创建preview-develop分支和对应preview-build-cache分支，rel-6.0.0将创建rel-6.0.0-develop分支的对应rel-6.0.0--build-cache分支
