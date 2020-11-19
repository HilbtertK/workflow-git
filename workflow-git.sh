#!/bin/bash

# git分支合并与管理工具
#========================
# 命令说明
# new: 从主分支/基准分支拉出新的开发分支
# init: 创建用于缓存已合并分支的build-cache分支和用于整合所有代码的develop分支
# ci: 将本分支的代码合入develop分支，并同时整合其他已合并分支的最新代码；如有自己分支的冲突，直接解决并强制提交
# init-sub: submodule的init操作
# ci-sub: submodule的ci操作
#========================
# 可通过在init和ci时指定prefix来区分不同环境/不同版本的dev分支
# 如设置prefix为preview将创建preview-develop分支和对应preview-build-cache分支，rel-6.0.0将创建rel-6.0.0-develop分支的对应rel-6.0.0--build-cache分支
#========================

checkout_branch_with_submodule_update() {
    local branch=$1
    git checkout $branch
    git submodule update
}

checkout_with_cache() {
    local branch=$1
    local service_env=$2
    local build_cache_branch=${service_env}-build-cache

    rm -rf $tmp_cache_dir

    checkout_branch_with_submodule_update $build_cache_branch
    git reset --hard origin/$build_cache_branch

    cp -r $build_cache_dir $tmp_cache_dir
    checkout_branch_with_submodule_update $branch
}

save_cache() {
    local service_env=$1
    local msg=$2
    local build_cache_branch=${service_env}-build-cache

    checkout_branch_with_submodule_update $build_cache_branch
    git reset --hard origin/$build_cache_branch

    if [ ! -x "$build_dir" ]; then
        mkdir -p $build_dir
    fi
    rm -rf $build_cache_dir
    cp -r $tmp_cache_dir $build_cache_dir
    rm -rf $tmp_cache_dir

    git add .
    git commit -m "[AUTO ${service_env} SCRIPT] $msg"
    git push -f --set-upstream origin $build_cache_branch
}

[[ $# -lt 1 ]] && echo "Usage: $0 (init|ci|new|init-sub|ci-sub)" && echo "Specify --help for available options" && exit 1

cmd=${1}
cache_dir=".cache"
tmp_cache_dir=".git/$cache_dir"
build_dir="build"
build_cache_dir="build/$cache_dir"
merge_branch_cache=".git/.cache/.merged-branches.cache"
default_base_branch="master"
default_prefix="merge"

case "$cmd" in
--help)
    echo 'bash workflow-git.sh <command> [option] [option]'
    echo 'where <command> is one of:'
    echo '  init,ci,new,init-sub,ci-sub'
    echo 'Configuration:'
    echo '  new <branch name> [base branch]                        create a new branch from base branch'
    echo '  init [prefix] [base branch]                            init build-cache branch and develop branch'
    echo '  ci [prefix] [base branch]                              merge current feature branch'
    echo "  init-sub <submodule path> [prefix] [base branch]       init submodule's build-cache branch and develop branch"
    echo "  ci-sub <submodule path> [prefix] [base branch]         merge submodule's current feature branch"
    ;;
new)
    [[ $# -lt 2 || $# -gt 3 ]] && echo "Usage: $0 new <branch name> [base branch]" && exit 1
    git fetch --all
    new_branch=$2
    if [ ! $3 ]; then
        base_branch=$default_base_branch
    else
        base_branch=$3
    fi
    checkout_branch_with_submodule_update $base_branch
    git reset --hard origin/$base_branch
    git checkout -b $new_branch
    ;;
init)
    [[ $# -lt 2 || $# -gt 3 ]] && echo "Usage: $0 init [prefix] [base branch]" && exit 1
    git fetch --all
    if [ ! $2 ]; then
        service_env=$default_prefix
    else
        service_env=$2
    fi
    if [ ! $3 ]; then
        base_branch=$default_base_branch
    else
        base_branch=$3
    fi
    new_build_cache_branch=${service_env}-build-cache
    new_develop_branch=${service_env}-develop
    checkout_branch_with_submodule_update $base_branch
    git reset --hard origin/$base_branch
    if [[ -n "$(git ls-remote origin ${new_build_cache_branch})" ]]; then
        echo "already init ${new_build_cache_branch}！"
    else
        git checkout -b $new_build_cache_branch
        git push origin $new_build_cache_branch
        checkout_branch_with_submodule_update $base_branch
    fi
    if [[ -n "$(git ls-remote origin ${new_develop_branch})" ]]; then
        echo "already init ${new_develop_branch}！"
    else
        git checkout -b $new_develop_branch
        git push origin $new_develop_branch
        checkout_branch_with_submodule_update $base_branch
    fi
    ;;
ci)
    [[ $# -lt 2 || $# -gt 3 ]] && echo "Usage: $0 ci [prefix] [base branch]" && exit 1

    if [[ -n "$(git status --porcelain)" ]]; then
        echo "ci时不能有未提交的修改"
        exit 1
    fi
    git fetch --all
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [ ! $2 ]; then
        service_env=$default_prefix
    else
        service_env=$2
    fi
    if [ ! $3 ]; then
        base_branch=$default_base_branch
    else
        base_branch=$3
    fi
    remote_integration_branch=${service_env}-develop

    git rebase origin/$base_branch

    # rebase fail
    if [ $? -ne 0 ]; then
        echo "rebase失败，请手动合并！"
        exit 1
    fi

    git push -f --set-upstream origin $branch

    checkout_with_cache $branch $service_env
    for line in $(cat $merge_branch_cache)
    do
        if [[ -n "$(git ls-remote origin ${line})" ]]; then
            echo "==> sync branch ${line}"
            checkout_branch_with_submodule_update $line
            git reset --hard origin/$line
            git rebase origin/$base_branch
            git push -f --set-upstream origin $line
        fi
    done

    checkout_branch_with_submodule_update $remote_integration_branch
    git reset --hard origin/$base_branch

    declare -a temp_arr
    i=0
    for line in $(cat $merge_branch_cache)
    do
        if [[ -n "$(git ls-remote origin ${line})" ]]; then
            if [[ "$line" != "$branch" ]]; then
                echo "==> rebase branch ${line}"
                git rebase origin/$line
                if [ $? -ne 0 ]; then
                    echo "**********************************************************************"
                    echo "*** rebase失败，请联系冲突所在分支的开发人员回到开发分支进行解决，不可强制提交 ***"
                    echo "**********************************************************************"
                    exit 1
                fi
                temp_arr[$i]=$line
                i++
            fi
        fi
    done
    temp_arr[$i]=$branch
    if [ ! -x "$tmp_cache_dir" ]; then
        mkdir $tmp_cache_dir
    fi
    echo > $merge_branch_cache
    for item in ${temp_arr[@]}
    do
        echo $item >> $merge_branch_cache
    done
    save_cache "$service_env" "merge branch: $branch"
    checkout_branch_with_submodule_update $remote_integration_branch
    git rebase origin/$branch
    if [ $? -ne 0 ]; then
        echo "*********************************************************************************"
        echo "*** rebase失败，请手动解决冲突后强制提交当前${remote_integration_branch}分支以完成合并 ***"
        echo "*********************************************************************************"
        exit 1
    fi
    git push -f --set-upstream origin $remote_integration_branch
    checkout_branch_with_submodule_update $branch
    git push -f --set-upstream origin $branch
    echo "分支合并完成"
    ;;
init-sub)
    [ $# -gt 4 || $# -lt 2 ]] && echo "Usage: $0 init-sub <submodule path> [prefix] [base branch]" && exit 1
    if [ ! $3 ]; then
        service_env=$default_prefix
    else
        service_env=$3
    fi
    if [ ! $4 ]; then
        base_branch=$default_base_branch
    else
        base_branch=$4
    fi
    sub_path=$2
    cd $sub_path
    git fetch --all
    new_build_cache_branch=${service_env}-build-cache
    new_develop_branch=${service_env}-develop
    checkout_branch_with_submodule_update $base_branch
    git reset --hard origin/$base_branch
    if [[ -n "$(git ls-remote origin ${new_build_cache_branch})" ]]; then
        echo "already init ${new_build_cache_branch}！"
    else
        git checkout -b $new_build_cache_branch
        git push origin $new_build_cache_branch
        checkout_branch_with_submodule_update $base_branch
    fi
    if [[ -n "$(git ls-remote origin ${new_develop_branch})" ]]; then
        echo "already init ${new_develop_branch}！"
    else
        git checkout -b $new_develop_branch
        git push origin $new_develop_branch
        checkout_branch_with_submodule_update $base_branch
    fi
    cd -
    ;;
ci-sub)
    [[ $# -gt 4 || $# -lt 2 ]] && echo "Usage: $0 ci-sub <submodule path> [prefix] [base branch]" && exit 1
    sub_path=$2
    cd $sub_path
    git fetch --all
    path_arr=`echo ${sub_path} | tr '/' ' '`
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "ci时不能有未提交的修改"
        exit 1
    fi

    branch=$(git rev-parse --abbrev-ref HEAD)
    if [ ! $3 ]; then
        service_env=$default_prefix
    else
        service_env=$3
    fi
    if [ ! $4 ]; then
        base_branch=$default_base_branch
    else
        base_branch=$4
    fi
    remote_integration_branch=${service_env}-develop

    git rebase origin/$base_branch

    # rebase fail
    if [ $? -ne 0 ]; then
        echo "rebase失败，请手动合并！"
        exit 1
    fi

    git push -f --set-upstream origin $branch
    merge_branch_cache_prefix=""
    for path_item in ${path_arr[@]}
    do
        merge_branch_cache_prefix="$merge_branch_cache_prefix../"
    done
    tmp_cache_dir=$merge_branch_cache_prefix$tmp_cache_dir
    merge_branch_cache=$merge_branch_cache_prefix$merge_branch_cache
    checkout_with_cache $branch $service_env
    for line in $(cat $merge_branch_cache)
    do
        if [[ -n "$(git ls-remote origin ${line})" ]]; then
            echo "==> sync branch ${line}"
            checkout_branch_with_submodule_update $line
            git reset --hard origin/$line
            git rebase origin/$base_branch
            git push -f --set-upstream origin $line
        fi
    done

    checkout_branch_with_submodule_update $remote_integration_branch
    git reset --hard origin/$base_branch

    declare -a temp_arr
    i=0
    for line in $(cat $merge_branch_cache)
    do
        if [[ -n "$(git ls-remote origin ${line})" ]]; then
            if [[ "$line" != "$branch" ]]; then
                echo "==> rebase branch ${line}"
                git rebase origin/$line
                if [ $? -ne 0 ]; then
                    echo "**********************************************************************"
                    echo "*** rebase失败，请联系冲突所在分支的开发人员回到开发分支进行解决，不可强制提交 ***"
                    echo "**********************************************************************"
                    exit 1
                fi
                temp_arr[$i]=$line
                i++
            fi
        fi
    done
    temp_arr[$i]=$branch
    if [ ! -x "$tmp_cache_dir" ]; then
        mkdir $tmp_cache_dir
    fi
    echo > $merge_branch_cache
    for item in ${temp_arr[@]}
    do
        echo $item >> $merge_branch_cache
    done
    save_cache "$service_env" "merge branch: $branch"
    checkout_branch_with_submodule_update $remote_integration_branch
    git rebase origin/$branch
    if [ $? -ne 0 ]; then
        echo "*********************************************************************************"
        echo "*** rebase失败，请手动解决冲突后强制提交当前${remote_integration_branch}分支以完成合并 ***"
        echo "*********************************************************************************"
        exit 1
    fi
    git push -f --set-upstream origin $remote_integration_branch
    checkout_branch_with_submodule_update $branch
    git push -f --set-upstream origin $branch
    cd -
    echo "submodule分支合并完成"
    ;;
*)
    echo "无效命令 $cmd"
    ;;
esac
