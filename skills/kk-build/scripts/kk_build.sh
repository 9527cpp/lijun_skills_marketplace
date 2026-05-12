#/**
# * Copyright (c) 2026 Oray Inc. All rights reserved.
# *
# * No Part of this file may be reproduced, stored
# * in a retrieval system, or transmitted, in any form, or by any means,
# * electronic, mechanical, photocopying, recording, or otherwise,
# * without the prior consent of Oray Inc.
# *
# * @author: LiJun
# * @date: 2026-02-05
# * @fileName: kk_build.sh
# * @description: 用于一键编译控控向日葵(含依赖的第三方库, 插件工程, 主程序等)
# */
#
file_header_str="
# ==============================================================================
# 文件名称: kk_build.sh
# 功能描述: 用于方便编译控控sunloginclient项目的本地构建脚本(俗称控控新向日葵一键编译)，
#          为什么说是本地,因为进入的目录编译的是不会去切分支的,直接拿当前分支git进行编译,而且打包的插件的动态库也是从本地编译出来进行打包的,并非handcake/linux下载的
#          支持模块编译和主程序编译和3rd库编译的灵活控制.
#          且为了方便后续有新的交叉编译需求,进行拓展.
#          脚本支持指定交叉编译工具链路径和目标平台.
#          我们kk_build.sh脚本支持参数解析、编译逻辑、错误处理，加上模块上传功能配制而成，不须复杂配置，也没有冗余代码，除了功能强大之外，使用还很简单。实属项目构建、模块编译、开发必备良器！
#          (仅限内部使用，禁止外泄.)
#
# 作    者: 9527cpp 
# 创建日期: 2026-02-05
# 版    本: 1.0
#
# 参数说明:
#   --cross_chain <path>   指定交叉编译工具链路径 (必填)
#   --target <target>      指定目标平台 (必填, 如 arm-openwrt-linux, aarch64-openwrt-linux)
#   --modules <modules>    指定要编译的模块列表,也就是向日葵的插件，空格分隔 (可选，指定后只编译模块)
#   --main                 只编译主程序 (可选)
#   --debug                启用Debug模式编译 (可选，默认Release模式)
#   --pack                 仅执行打包操作，不进行编译 (可选，需配合--target使用)
#   --quiet                静默模式，所有编译输出重定向到/dev/null (默认: 关闭) 
#   --no_upload            不上传编译结果 (可选，默认上传)
#   --module_path <name> <path>  指定单个模块的源码路径 (可选，可多次使用)
#   --help                 显示帮助信息
#
# 使用前提:
#   1. 确保已经安装了必要的编译工具和库(如gcc, make, cmake等)
#   2. 确保已经设置了交叉编译工具链的环境变量(如PATH), 或者使用--cross_chain参数指定
#   3. 向日葵插件代码就在主工程同级目录 $(pwd)/modules/client/xxxx 形式 
#   4. 编译主控程依赖的modules,注意需要在modules.json中提前更新对应目标平台3rd的包id与各个插件的commit id(甚至是一些依赖到的sl-control的包的commit id,而且这些包需要提前上传上去)
#
# 使用示例:
#   1. 编译默认Release的模块和主程序,以及打包和上传:
#      ./kk_build.sh --cross_chain /path/to/toolchain --target arm-openwrt-linux
#   2. 编译Debug的模块和主程序:
#      ./kk_build.sh --cross_chain /path/to/toolchain --target arm-openwrt-linux --debug
#   3. 只编译指定模块:
#      ./kk_build.sh --cross_chain /path/to/toolchain --target arm-openwrt-linux --modules usbip
#   4. 只编译主程序:
#      ./kk_build.sh --cross_chain /path/to/toolchain --target arm-openwrt-linux --main
#   5. 仅执行打包操作:
#      ./kk_build.sh --cross_chain /path/to/toolchain --target arm-openwrt-linux --pack
#   7. 静默模式编译:
#      ./kk_build.sh --cross_chain /path/to/toolchain --target arm-openwrt-linux --quiet
#   8. 不上传编译结果:
#      ./kk_build.sh --cross_chain /path/to/toolchain --target arm-openwrt-linux --no_upload
#   9. 显示帮助信息:
#      ./kk_build.sh --help
#  10. 指定模块源码路径(可多次使用):
#      ./kk_build.sh --cross_chain /path/to/toolchain --target arm-openwrt-linux --module_path desktop /path/to/desktop --module_path usbip /path/to/usbip
#
# 注意事项:
#   1. 请确保脚本在向日葵主工程目录下执行
#   2. 请确保脚本有执行权限
#
# 若无任何特殊需求，直接按照 示例1 即可一键编译打包
# 如有任何使用上的问题，请联系作者 - 李君. (QQ: 2291042162@qq.com, TEL: 13003228662)
# ==============================================================================
"
declare -g no_upload=false
declare -A module_paths=()  # 存储 module_name -> path 的映射
declare -g project_root=""   # 项目根目录，默认使用 pwd

#!/bin/bash

################# log control #################
print_colored() {
    local text="$1"
    local color="$2"
    local code=""
    
    case $color in
        red)    code="\033[31m" ;;   # 红色
        green)  code="\033[32m" ;;   # 绿色
        yellow) code="\033[33m" ;;   # 黄色
        blue)   code="\033[34m" ;;   # 蓝色
        purple) code="\033[35m" ;;   # 紫色
        cyan)   code="\033[36m" ;;   # 青色
        *)      code="" ;;           # 默认无颜色
    esac
    
    if [ -n "$code" ]; then
        echo -e "${code}${text}\033[0m"
    else
        echo "$text"
    fi
}

info_msg() {
    print_colored "[INFO]: $1" green
}
warn_msg() {
    print_colored "[WARN]: $1" "yellow"
}
error_msg() {
    print_colored "[ERROR]: $1" "red"
}
debug_msg() {
    print_colored "[DEBUG]: $1" "blue"
}

print_help() {
    print_colored "$file_header_str" "cyan"
    cat << 'EOF'
用法: ./kk_build.sh --cross_chain <path> --target <target> [选项]

必填参数:
  --cross_chain <path>    交叉编译工具链路径 (如 /path/to/toolchain)
  --target <target>       目标平台 (如 arm-openwrt-linux, aarch64-openwrt-linux,
                          arm-rockchip830-linux-uclibcgnueabihf)

可选参数:
  --modules <modules>    指定要编译的模块列表，空格分隔
                          (默认: desktop audio usbip ssh camera file kk)
  --main                  仅编译主程序
  --3rd [libs]          仅编译第三方依赖库，可指定库名(逗号分隔)
                          如: --3rd openssl,fftw 或不指定则编译所有
  --debug                 启用Debug模式编译，默认Release
  --pack                  仅执行打包操作，不编译
  --quiet                 静默模式，编译输出重定向到/dev/null
  --no_upload             不上传编译结果，默认上传
  --project_root <path>  项目根目录 (默认: 当前目录)
  --module_path <name> <path>  指定模块的自定义源码路径
  --help                  显示帮助信息

示例:
  # 完整编译(模块+主程序+kk接口)并打包上传
  ./kk_build.sh --cross_chain /path/to/toolchain --target arm-openwrt-linux

  # 指定模块自定义路径
  ./kk_build.sh --cross_chain /path/toolchain --target arm-openwrt-linux \
      --module_path desktop /path/to/desktop/source

  # Debug模式编译
  ./kk_build.sh --cross_chain /path/to/toolchain --target arm-openwrt-linux --debug
EOF
}
################################################# 


################# compile control #################
# 模块批量编译函数（使用全局参数）
compile_modules() {
    local modules=($1)  # 仅接收模块列表参数
    local debug_flag=""

    # 检查全局参数是否已设置
    if [ -z "$cross_chain" ] || [ -z "$target" ]; then
        error_msg "cross_chain和target参数必须设置"
        exit 1
    fi
    if [ "$debug_mode" = true ]; then
        debug_flag="-d"
    fi

    # 进入项目根目录
    cd "$project_root" || { error_msg "无法进入项目根目录: $project_root"; exit 1; }

    for module in "${modules[@]}"; do
        # 优先使用用户指定的路径，否则使用默认的 modules/client/
        if [[ -n "${module_paths[$module]}" ]]; then
            local base_path="${module_paths[$module]}"
        else
            local base_path="modules/client"
        fi
        local module_path="${base_path}/${module}"
        local upload_path="http://devres.oray.net/oraylibs/sunlogin/sl-client-${module}"

        local upload_param=""
        if [ "$no_upload" = false ]; then
            upload_param="-r $upload_path"
        fi
        
        if [ -d "${module_path}" ]; then
            info_msg "开始编译模块: ${module}" 
            cd "${module_path}" || { error_msg "无法进入目录: ${module_path}"; continue; }
            # git_version=$(git log --oneline -n 1 | cut -d' ' -f1)
            git_version=$(git rev-parse --short=8 HEAD)

            # 使用全局参数构建编译命令
            eval "python deps/slpackage/script/cmake_build.py \
                -p linux $debug_flag \
                -a '${target}' \
                -c '-DCROSS_CHAIN_PATH=${cross_chain}' \
                -t "${target}" \
                -m 'client_${module}' \
                -n '${git_version}'  \
                $upload_param \
                $redirect_flag"

            if [ $? -eq 0 ]; then
                info_msg "模块${module}编译成功" 
            else
                error_msg "模块${module}编译失败"
                exit 1  # 如果需要继续编译其他模块可移除此行
            fi
            cd - > /dev/null
        else
            warn_msg "模块路径不存在: ${module_path}, 将跳过此模块的编译" 
        fi
    done
}


# 编译主程序
compile_main() {
    info_msg "开始编译主程序..."

    local debug_flag=""
    # 检查必要的参数是否已设置
    if [ -z "$cross_chain" ] || [ -z "$target" ]; then
        error_msg "cross_chain和target参数必须设置"
        return 1
    fi

    # 进入项目根目录
    cd "$project_root" || { error_msg "无法进入项目根目录: $project_root"; return 1; }

    if [ "$debug_mode" = true ]; then
        debug_flag="-d"
    fi
    # 执行编译命令，替换cross_chain和target参数
    python auto_compile.py -p linux $debug_flag -a "$target" -t cli \
        -c "-DCROSS_CHAIN_PATH=$cross_chain,-DCMAKE_VERBOSE_MAKEFILE=ON" \
        -T "$target" $redirect_flag

    # 检查编译结果
    if [ $? -eq 0 ]; then
        info_msg "主程序编译成功!"
    else
        error_msg "主程序编译失败!"
        return 1
    fi
}


# fftw 3.3.10 编译函数
compile_fftw_3.3.10() {
    local fftw_version="3.3.10"
    local fftw_dir="fftw-${fftw_version}"
    local fftw_tar="${fftw_dir}.tar.gz"
    local fftw_url="https://www.fftw.org/${fftw_tar}"

    # 检查是否已存在源码目录
    if [ ! -d "${fftw_dir}" ]; then
        info_msg "FFTW ${fftw_version} 源码目录不存在，开始下载..." 

        # 下载源码包
        if ! wget "${fftw_url}" -O "${fftw_tar}"; then
            error_msg "错误: 无法下载FFTW源码包 ${fftw_url}"
            return 1
        fi

        # 解压源码包
        info_msg "正在解压 ${fftw_tar}..." 
        if ! tar -zxvf "${fftw_tar}"; then
            error_msg "错误: 无法解压 ${fftw_tar}"
            rm -f "${fftw_tar}"  # 清理下载失败的文件
            return 1
        fi

        # 清理压缩包
        rm -f "${fftw_tar}"
    fi

    # 进入源码目录
    cd "${fftw_dir}" || { error_msg "错误: 无法进入目录 ${fftw_dir}" ; return 1; }
    if [ -f "Makefile" ]; then
        eval "make clean ${redirect_flag}" || { error_msg "fftw清理失败"; return 1; }
    fi

    # 检查交叉编译工具链
    local cc_path="${cross_chain}/bin/${target}-gcc"
    if [ ! -x "${cc_path}" ]; then
        error_msg "错误: 交叉编译工具链不存在 ${cc_path}" 
        return 1
    fi

    # 配置编译选项
    info_msg "正在配置FFTW ${fftw_version}..." 
    if ! ./configure \
        CC="${cc_path}" \
        --enable-float \
        --host="${target}" $redirect_flag
    then
        error_msg "错误: FFTW配置失败" 
        return 1
    fi

    # 编译源码
    info_msg "正在编译FFTW ${fftw_version}..." 
    if ! make -j$(nproc) $redirect_flag; then
        error_msg "错误: FFTW编译失败" 
        return 1
    fi

    cd .. || return 1
    info_msg "FFTW ${fftw_version} 编译成功" 
    return 0
}

# 打包fftw 3.3.10库函数
# 生成的文件结构类似handcake/linux/fftw-arm-openwrt-linux
# 最终生成的文件为fftw_3.3.10-linux-${target}-1.zip
pack_fftw_3.3.10() {
    local fftw_version="3.3.10"
    local src_dir="fftw-${fftw_version}"
    local build_version="1"
    local output_zip="fftw-${fftw_version}-linux-${target}-${build_version}.zip"
    local temp_pack_dir="handcake/linux/fftw-${target}"
    
    info_msg "开始打包fftw ${fftw_version}..."
    
    # 检查目标路径参数
    if [ -z "${target}" ]; then
        error_msg "错误: 未指定target参数，无法执行打包操作"
        return 1
    fi
    
    # 检查源码目录是否存在
    if [ ! -d "${src_dir}" ]; then
        error_msg "错误: fftw源码目录不存在: ${src_dir}"
        return 1
    fi
    
    # 清理之前的打包文件
    rm -rf "${temp_pack_dir}" "${output_zip}"
    
    # 创建目标目录结构
    info_msg "创建打包目标目录结构: ${temp_pack_dir}"
    mkdir -p "${temp_pack_dir}/lib"
    mkdir -p "${temp_pack_dir}/include"
    
    # 复制库文件
    info_msg "复制库文件..."
    # 静态库 - 注意fftw的库文件在.libs目录下
    if [ -f "${src_dir}/.libs/libfftw3f.a" ]; then
        cp "${src_dir}/.libs/libfftw3f.a" "${temp_pack_dir}/lib/"
        info_msg "已复制静态库: libfftw3f.a"
    else
        warn_msg "警告: 静态库文件不存在: ${src_dir}/.libs/libfftw3f.a"
    fi
    
    # 复制.la文件
    if [ -f "${src_dir}/.libs/libfftw3f.la" ]; then
        cp "${src_dir}/.libs/libfftw3f.la" "${temp_pack_dir}/lib/"
        info_msg "已复制库描述文件: libfftw3f.la"
    fi
    
    # 复制头文件
    info_msg "复制头文件..."
    if ls "${src_dir}/api/fftw3.h" 1> /dev/null 2>&1; then
        cp "${src_dir}/api/fftw3.h" "${temp_pack_dir}/include/"
        info_msg "已复制头文件: fftw3.h"
    else
        warn_msg "警告: 头文件不存在: ${src_dir}/api/fftw3.h"
    fi
    
    # 复制其他可能的头文件
    if ls "${src_dir}/api/fftw3f.f03" 1> /dev/null 2>&1; then
        cp "${src_dir}/api/fftw3f.f03" "${temp_pack_dir}/include/"
        info_msg "已复制头文件: fftw3f.f03"
    fi
    
    if ls "${src_dir}/api/fftw3l.f03" 1> /dev/null 2>&1; then
        cp "${src_dir}/api/fftw3l.f03" "${temp_pack_dir}/include/"
        info_msg "已复制头文件: fftw3l.f03"
    fi
    
    if ls "${src_dir}/api/fftw3q.f03" 1> /dev/null 2>&1; then
        cp "${src_dir}/api/fftw3q.f03" "${temp_pack_dir}/include/"
        info_msg "已复制头文件: fftw3q.f03"
    fi
    
    # 创建zip包
    info_msg "创建zip包: ${output_zip}"

    cd "${temp_pack_dir}" || { error_msg "无法进入handcake目录"; return 1; }
    zip -rq "../../../${output_zip}" . $redirect_flag || {

        error_msg "创建zip包失败"
        cd - > /dev/null || return 1
        return 1
    }
    cd - > /dev/null || return 1
    
    # 清理临时目录
    rm -rf "${temp_pack_dir}"
    
    info_msg "fftw ${fftw_version} 打包完成，生成文件: ${output_zip}"
    return 0
}

# 编译zlib 1.2.3库
# 依赖: git, 交叉编译工具链
compile_zlib_1.2.3() {
    local zlib_dir="zlib-1.2.3"
    #local repo_url="https://github.com/madler/zlib.git"
    local repo_url="https://gitee.com/Geoyee/zlib.git"
    local branch="v1.2.3"
    local install_prefix="${PWD}/${zlib_dir}/_install"

    # 检查源码目录是否存在
    if [ ! -d "${zlib_dir}" ]; then
        info_msg "zlib源码目录不存在，开始克隆仓库..."
        if ! git clone "${repo_url}" "${zlib_dir}"; then
            error_msg "克隆zlib仓库失败"
            return 1
        fi
    fi

    # 进入源码目录并切换分支
    if ! cd "${zlib_dir}"; then
        error_msg "无法进入zlib源码目录: ${zlib_dir}"
        return 1
    fi

    info_msg "切换到zlib ${branch}分支..."
    if ! git checkout "${branch}"; then
        error_msg "切换到${branch}分支失败"
        cd .. || return 1
        return 1
    fi

    # 配置交叉编译环境变量
    info_msg "配置交叉编译工具链..."
    export CC="${cross_chain}/bin/${target}-gcc"
    export CXX="${cross_chain}/bin/${target}-g++"
    # export AR="${cross_chain}/bin/${target}-ar"

    # 注意: 该交叉编译器在生成静态库时因没配置rcs 导致 ar失败, 这里是投机取巧了 把参数也带入了 
    export AR="${cross_chain}/bin/${target}-ar rcs"
    export RANLIB="${cross_chain}/bin/${target}-ranlib"

    # 注意: 禁止交叉编译器报staging_dir的警告打出来,造成zlib errno 检测过不了
    export STAGING_DIR=$cross_chain/bin/${target}

    # 检查环境变量是否配置成功
    if [ -z "${CC}" ] || [ ! -x "$(command -v ${CC})" ]; then
        error_msg "交叉编译器配置失败: ${CC}不存在或不可执行"
        cd .. || return 1
        return 1
    fi

    # 检查Makefile是否存在，如果存在则执行make clean
    if [ -f "Makefile" ]; then
        eval "make clean ${redirect_flag}" || { error_msg "zlib清理失败"; cd - > /dev/null || return 1; return 1; }
    fi

    # 配置编译选项
    info_msg "开始配置zlib..."

    # 打个小patch, zlib --shared 就不能编译静态库了, 这里修改configure 使得 --shared 时,能同时生成静态库和动态库
    if [ -f "./configure" ]; then
        info_msg "修改configure文件第177行..."
        #sed -i '177s/LIBS="\$SHAREDLIBV"/LIBS+=" \$SHAREDLIBV"/' configure
        if [ $? -ne 0 ]; then
            warn_msg "修改configure文件失败，但继续执行..."
        fi
    fi


    ## compile shared
    if ! ./configure --shared $redirect_flag; then
        error_msg "zlib配置失败"
        cd .. || return 1
        return 1
    fi

    # 编译并安装
    info_msg "开始编译zlib..."
    if ! make -j$(nproc) $redirect_flag; then
        error_msg "zlib编译失败"
        cd .. || return 1
        return 1
    fi

    # 返回到调用目录并清理环境变量
    cd .. || return 1
    unset CC CXX AR RANLIB
    info_msg "zlib 1.2.3编译成功"
    return 0
}


# 打包zlib 1.2.3库
# 依赖: 已编译的zlib库
pack_zlib_1.2.3() {
    local zlib_version="1.2.3"
    local build_version="1"
    local zlib_dir="zlib-1.2.3"
    local output_zip="zlib-${zlib_version}-linux-${target}-${build_version}.zip"
    local temp_pack_dir="handcake/linux/zlib-${target}"
    
    info_msg "开始打包zlib ${zlib_version}..."
    
    # 检查源码目录是否存在
    if [ ! -d "${zlib_dir}" ]; then
        error_msg "zlib源码目录不存在: ${zlib_dir}"
        return 1
    fi
    
    # 检查编译产物是否存在
    #if [ ! -f "${zlib_dir}/libz.a" ]; then
    #    error_msg "zlib库文件不存在，请先编译: ${zlib_dir}/libz.a"
    #    return 1
    #fi
    
    # 创建临时打包目录
    rm -rf "${temp_pack_dir}"
    mkdir -p "${temp_pack_dir}/lib" "${temp_pack_dir}/include" || {
        error_msg "创建临时打包目录失败"
        return 1
    }
    
    # 复制静态库
    cp -f "${zlib_dir}/libz.a" "${temp_pack_dir}/lib/" || {
        error_msg "复制zlib静态库失败"
        return 1
    }

    # 复制动态库
    cp -f ${zlib_dir}/libz.so* "${temp_pack_dir}/lib/" || {
        error_msg "复制zlib动态库失败"
        return 1
    }
    
    # 复制头文件
    cp -f "${zlib_dir}/zlib.h" "${zlib_dir}/zconf.h" "${temp_pack_dir}/include/" || {
        error_msg "复制zlib头文件失败"
        return 1
    }
    
    # 创建zip包
    cd "${temp_pack_dir}" || { error_msg "无法进入handcake目录"; return 1; }
    zip -rq "../../../${output_zip}" . $redirect_flag || {
        error_msg "创建zip包失败"
        cd - > /dev/null || return 1
        return 1
    }
    cd - > /dev/null || return 1
    
    # 清理临时目录
    rm -rf "${temp_pack_dir}"
    
    info_msg "zlib ${zlib_version} 打包完成，生成文件: ${output_zip}"
    return 0
}


# 编译protobuf 3.15.8库
# 依赖: git, 交叉编译工具链
compile_protobuf_3.15.8() {
    local src_dir="protobuf"
    local repo_url="https://github.com/protocolbuffers/protobuf.git"
    local branch="3.15.x"
    
    info_msg "开始编译protobuf 3.15.8..."

    # 克隆仓库如果目录不存在
    if [ ! -d "${src_dir}" ]; then
        info_msg "从${repo_url}克隆protobuf仓库..."
        git clone ${repo_url} ${src_dir} || { error_msg "protobuf仓库克隆失败"; return 1; }
    fi

    # 进入源码目录
    cd ${src_dir} || { error_msg "无法进入${src_dir}目录"; return 1; }

    # 检查Makefile是否存在，如果存在则执行make clean
    if [ -f "Makefile" ]; then
        eval "make clean ${redirect_flag}" || { error_msg "protobuf清理失败"; return 1; }
    fi

    # 切换到指定分支
    info_msg "切换到${branch}分支..."
    git checkout ${branch} || { error_msg "切换到${branch}分支失败"; return 1; }

    # 生成配置脚本
    info_msg "执行autogen.sh生成配置文件..."
    ./autogen.sh || { error_msg "autogen.sh执行失败"; return 1; }

    # 配置交叉编译
    info_msg "配置protobuf交叉编译环境..."
    ./configure --host=${target} \
        CC="${cross_chain}/bin/${target}-gcc" \
        CXX="${cross_chain}/bin/${target}-g++" || { error_msg "configure执行失败"; return 1; }

    # 编译源码
    info_msg "开始编译protobuf..."

    if ! make -j$(nproc) $redirect_flag; then
        error_msg "protobuf编译失败"
        cd .. || return 1
        return 1
    fi

    info_msg "protobuf 3.15.8编译完成"
    cd - > /dev/null || return 1  # 返回原目录
}

# 打包protobuf 3.15.8库
# 依赖: 已编译的protobuf库
pack_protobuf_3.15.8() {
    local protobuf_version="3.15.8"
    local build_version="1"
    local protobuf_dir="protobuf"
    local output_zip="protobuf-${protobuf_version}-linux-${target}-${build_version}.zip"
    local temp_pack_dir="handcake/linux/protobuf-${target}"
    
    info_msg "开始打包protobuf ${protobuf_version}..."
    
    # 检查源码目录是否存在
    if [ ! -d "${protobuf_dir}" ]; then
        error_msg "protobuf源码目录不存在: ${protobuf_dir}"
        return 1
    fi
    
    # 检查编译产物是否存在
    if [ ! -f "${protobuf_dir}/src/.libs/libprotobuf.a" ]; then
        error_msg "protobuf库文件不存在，请先编译: ${protobuf_dir}/src/.libs/libprotobuf.a"
        return 1
    fi
    
    # 创建临时打包目录
    rm -rf "${temp_pack_dir}"
    mkdir -p "${temp_pack_dir}/lib" "${temp_pack_dir}/include/google" || {
        error_msg "创建临时打包目录失败"
        return 1
    }
    
    # 复制库文件
    local lib_dir="${protobuf_dir}/src/.libs"
    
    # 复制静态库
    cp -f "${lib_dir}/libprotobuf.a" "${lib_dir}/libprotobuf-lite.a" "${lib_dir}/libprotoc.a" "${temp_pack_dir}/lib/" || {
        error_msg "复制protobuf静态库失败"
        return 1
    }
    
    # 复制动态库
    if [ -f "${lib_dir}/libprotobuf.so" ]; then
        cp -f "${lib_dir}/libprotobuf.so" "${lib_dir}/libprotobuf.so.26" "${lib_dir}/libprotobuf.so.26.0.8" "${temp_pack_dir}/lib/" || {
            warn_msg "复制protobuf动态库失败，但继续打包"
        }
    fi
    
    if [ -f "${lib_dir}/libprotobuf-lite.so" ]; then
        cp -f "${lib_dir}/libprotobuf-lite.so" "${lib_dir}/libprotobuf-lite.so.26" "${lib_dir}/libprotobuf-lite.so.26.0.8" "${temp_pack_dir}/lib/" || {
            warn_msg "复制protobuf-lite动态库失败，但继续打包"
        }
    fi
    
    if [ -f "${lib_dir}/libprotoc.so" ]; then
        cp -f "${lib_dir}/libprotoc.so" "${lib_dir}/libprotoc.so.26" "${lib_dir}/libprotoc.so.26.0.8" "${temp_pack_dir}/lib/" || {
            warn_msg "复制protoc动态库失败，但继续打包"
        }
    fi
    
    # 复制头文件
    local include_src_dir="${protobuf_dir}/src/google/protobuf"
    local include_dest_dir="${temp_pack_dir}/include/google/protobuf"
    
    mkdir -p "${include_dest_dir}" || {
        error_msg "创建头文件目录失败"
        return 1
    }
    
    # 复制所有头文件
    cp -f "${include_src_dir}"/*.h "${include_dest_dir}/" || {
        error_msg "复制protobuf头文件失败"
        return 1
    }
    
    # 复制所有头文件
    cp -f "${include_src_dir}"/*.proto "${include_dest_dir}/" || {
        error_msg "复制protobuf头文件失败"
        return 1
    }

    # 复制所有头文件
    cp -f "${include_src_dir}"/*.inc "${include_dest_dir}/" || {
        error_msg "复制protobuf头文件失败"
        return 1
    }


    # 复制子目录中的头文件
    for subdir in compiler io stubs util; do
        if [ -d "${include_src_dir}/${subdir}" ]; then
            mkdir -p "${include_dest_dir}/${subdir}" || {
                warn_msg "创建${subdir}子目录失败，但继续打包"
                continue
            }
            cp -f "${include_src_dir}/${subdir}"/*.h "${include_dest_dir}/${subdir}/" 2>/dev/null || {
                warn_msg "复制${subdir}目录下的头文件失败，但继续打包"
            }
        fi
    done
    
    # 创建zip包
    cd "${temp_pack_dir}" || { error_msg "无法进入handcake目录"; return 1; }
    zip -rq "../../../${output_zip}" . $redirect_flag || {
        error_msg "创建zip包失败"
        cd - > /dev/null || return 1
        return 1
    }
    cd - > /dev/null || return 1
    
    # 清理临时目录
    rm -rf "${temp_pack_dir}"
    
    info_msg "protobuf ${protobuf_version} 打包完成，生成文件: ${output_zip}"
    return 0
}


# 编译replxx 0.0.4库
# 依赖: git, 交叉编译工具链
compile_replxx_0.0.4() {
    local src_dir="replxx"
    local repo_url="https://gitcode.com/gh_mirrors/re/replxx.git" ## 要用户名密码
    # local repo_url="https://github.com/AmokHuginnsson/replxx.git"
    local branch="release-0.0.4"

    info_msg "开始编译replxx 0.0.4..."

    # 克隆仓库如果目录不存在
    if [ ! -d "${src_dir}" ]; then
        info_msg "从${repo_url}克隆replxx仓库..."
        git clone ${repo_url} ${src_dir} || { error_msg "replxx仓库克隆失败"; return 1; }
    fi

    # 进入源码目录
    cd ${src_dir} || { error_msg "无法进入${src_dir}目录"; return 1; }
    # eval "make clean ${redirect_flag}" || { error_msg "replxx清理失败"; return 1; }

    # 切换到指定分支
    info_msg "切换到${branch}分支..."
    git checkout ${branch} || { error_msg "切换到${branch}分支失败"; return 1; }

    # 设置CMake交叉编译环境变量
    info_msg "配置CMake交叉编译环境..."

    eval "sed -i '77s#.*#cmake -DCMAKE_C_COMPILER=${cross_chain}/bin/${target}-gcc -DCMAKE_CXX_COMPILER=${cross_chain}/bin/${target}-g++ -DCMAKE_BUILD_TYPE=${target} ${shared} ${examples} ${installPrefix} ../../#' ./build-all.sh"

    # 执行编译脚本
    info_msg "执行build_all.sh编译replxx..."
    eval "./build-all.sh $redirect_flag" || { error_msg "replxx编译失败"; return 1; }

    info_msg "replxx 0.0.4编译完成"
    cd - > /dev/null || return 1  # 返回原目录
}

# 打包replxx 0.0.4库函数
# 生成的文件结构类似handcake/linux/replxx-arm-openwrt-linux
# 最终生成的文件为replxx_0.0.4-linux-${target}-1.zip
pack_replxx_0.0.4() {
    local replxx_version="0.0.4"
    local src_dir="replxx"
    local build_version="1"
    local output_zip="replxx-${replxx_version}-linux-${target}-${build_version}.zip"
    local temp_pack_dir="handcake/linux/replxx-${target}"
    
    info_msg "开始打包replxx ${replxx_version}..."
    
    # 检查目标路径参数
    if [ -z "${target}" ]; then
        error_msg "错误: 未指定target参数，无法执行打包操作"
        return 1
    fi
    
    # 检查源码目录是否存在
    if [ ! -d "${src_dir}" ]; then
        error_msg "错误: replxx源码目录不存在: ${src_dir}"
        return 1
    fi
    
    # 清理之前的打包文件
    rm -rf "${temp_pack_dir}" "${output_zip}"
    
    # 创建目标目录结构
    info_msg "创建打包目标目录结构: ${temp_pack_dir}"
    mkdir -p "${temp_pack_dir}/lib"
    mkdir -p "${temp_pack_dir}/include"
    
    # 复制库文件
    info_msg "复制库文件..."
    # 静态库
    if [ -f "${src_dir}/build/release/libreplxx.a" ]; then
        cp "${src_dir}/build/release/libreplxx.a" "${temp_pack_dir}/lib/"
        info_msg "已复制静态库: libreplxx.a"
    else
        warn_msg "警告: 静态库文件不存在: ${src_dir}/build/release/libreplxx.a"
    fi
    
    # 动态库
    if [ -f "${src_dir}/build/release/libreplxx.so" ]; then
        cp "${src_dir}/build/release/libreplxx.so" "${temp_pack_dir}/lib/"
        info_msg "已复制动态库: libreplxx.so"
    fi
    
    if [ -f "${src_dir}/build/release/libreplxx.so.${replxx_version}" ]; then
        cp "${src_dir}/build/release/libreplxx.so.${replxx_version}" "${temp_pack_dir}/lib/"
        info_msg "已复制动态库: libreplxx.so.${replxx_version}"
    fi
    
    # 复制头文件
    info_msg "复制头文件..."
    if ls "${src_dir}/include"/*.h* 1> /dev/null 2>&1; then
        cp "${src_dir}/include"/*.h* "${temp_pack_dir}/include/"
        info_msg "已复制所有replxx头文件"
    else
        warn_msg "警告: replxx头文件不存在: ${src_dir}/include/*.h*"
    fi
    
    # 创建zip包
    info_msg "创建zip包: ${output_zip}"
    cd "${temp_pack_dir}" || { error_msg "无法进入handcake目录"; return 1; }
    zip -rq "../../../${output_zip}" . $redirect_flag || {
        error_msg "创建zip包失败"
        cd - > /dev/null || return 1
        return 1
    }
    cd - > /dev/null || return 1
    
    # 清理临时目录
    rm -rf "${temp_pack_dir}"
    
    info_msg "replxx ${replxx_version} 打包完成，生成文件: ${output_zip}"
    return 0
}

# 编译replxx 0.0.4库
# 依赖: git, 交叉编译工具链
compile_openssl_1.1.1q() {
    local src_dir="openssl-1.1.1q"
    local tarball="openssl-1.1.1q.tar.gz"
    local download_url="https://www.openssl.org/source/${tarball}"
    
    info_msg "开始编译openssl 1.1.1q..."

    # 检查源码目录是否存在
    if [ ! -d "${src_dir}" ]; then
        # 检查tarball是否已下载
        if [ ! -f "${tarball}" ]; then
            info_msg "从${download_url}下载openssl源码..."
            wget ${download_url} || { error_msg "openssl源码下载失败"; return 1; }
        fi

        # 解压tarball
        info_msg "解压${tarball}..."
        tar -zxf ${tarball} || { error_msg "openssl源码解压失败"; return 1; }
    fi

    # 进入源码目录
    cd ${src_dir} || { error_msg "无法进入${src_dir}目录"; return 1; }

    # 检查Makefile是否存在，如果存在则执行make clean
    if [ -f "Makefile" ]; then
        eval "make clean ${redirect_flag}" || { error_msg "openssl清理失败"; return 1; }
    fi

    # 配置编译选项
    info_msg "配置openssl交叉编译环境..."

    os="linux"
    if [ "$target" == "arm-openwrt-linux" ]; then
        os="${os}-armv4"
    elif [ "$target" == "aarch64-openwrt-linux" ]; then
        os="${os}-aarch64"
    elif [ "$target" == "arm-rockchip830-linux-uclibcgnueabihf" ]; then
        os="${os}-armv4"
    fi

    eval "./Configure ${os} \
        --prefix=/usr \
        --libdir=lib \
        --openssldir=/etc/ssl \
        --cross-compile-prefix='${target}-' \
        -znow -zrelro -Wl,--gc-sections \
        shared no-blake2 \
        -DOPENSSL_PREFER_CHACHA_OVER_GCM \
        no-async no-ec2m no-camellia no-idea no-seed no-mdc2 no-whirlpool no-rfc3779 \
        -DOPENSSL_SMALL_FOOTPRINT \
        no-afalgeng no-hw-padlock no-dtls no-comp no-nextprotoneg ${redirect_flag}" || { error_msg "openssl配置失败"; return 1; }

    # 编译
    info_msg "开始编译openssl..."
    eval "make -j $(nproc) CC='${cross_chain}/bin/${target}-gcc' \
         ARFLAGS='rcs' \
         AR='${cross_chain}/bin/${target}-ar' ${redirect_flag}" || { error_msg "openssl编译失败"; return 1; }

    info_msg "openssl 1.1.1q编译完成"
    cd - > /dev/null || return 1
}

# 打包openssl 1.1.1q库函数
# 生成的文件结构类似handcake/linux/openssl-arm-openwrt-linux
# 最终生成的文件为openssl_1.1.1q-linux-${target}-1.zip
pack_openssl_1.1.1q() {
    local openssl_version="1.1.1q"
    local src_dir="openssl-${openssl_version}"
    local build_version="1"
    local output_zip="openssl-${openssl_version}-linux-${target}-${build_version}.zip"
    local temp_pack_dir="handcake/linux/openssl-${target}"
    
    info_msg "开始打包openssl ${openssl_version}..."
    
    # 检查目标路径参数
    if [ -z "${target}" ]; then
        error_msg "错误: 未指定target参数，无法执行打包操作"
        return 1
    fi
    
    # 检查源码目录是否存在
    if [ ! -d "${src_dir}" ]; then
        error_msg "错误: openssl源码目录不存在: ${src_dir}"
        return 1
    fi
    
    # 清理之前的打包文件
    rm -rf "${temp_pack_dir}" "${output_zip}"
    
    # 创建目标目录结构
    info_msg "创建打包目标目录结构: ${temp_pack_dir}"
    mkdir -p "${temp_pack_dir}/lib"
    mkdir -p "${temp_pack_dir}/include/openssl"
    mkdir -p "${temp_pack_dir}/include/crypto"
    
    # 复制库文件
    info_msg "复制库文件..."
    # 静态库
    if [ -f "${src_dir}/libcrypto.a" ]; then
        cp "${src_dir}/libcrypto.a" "${temp_pack_dir}/lib/"
        info_msg "已复制静态库: libcrypto.a"
    else
        warn_msg "警告: 静态库文件不存在: ${src_dir}/libcrypto.a"
    fi
    
    if [ -f "${src_dir}/libssl.a" ]; then
        cp "${src_dir}/libssl.a" "${temp_pack_dir}/lib/"
        info_msg "已复制静态库: libssl.a"
    else
        warn_msg "警告: 静态库文件不存在: ${src_dir}/libssl.a"
    fi
    
    # 动态库
    if [ -f "${src_dir}/libcrypto.so" ]; then
        cp "${src_dir}/libcrypto.so" "${temp_pack_dir}/lib/"
        info_msg "已复制动态库: libcrypto.so"
    fi
    
    if [ -f "${src_dir}/libssl.so" ]; then
        cp "${src_dir}/libssl.so" "${temp_pack_dir}/lib/"
        info_msg "已复制动态库: libssl.so"
    fi
    
    # 复制头文件
    info_msg "复制头文件..."
    if ls "${src_dir}/include/openssl"/*.h 1> /dev/null 2>&1; then
        cp "${src_dir}/include/openssl"/*.h "${temp_pack_dir}/include/openssl/"
        info_msg "已复制所有openssl头文件"
    else
        warn_msg "警告: openssl头文件不存在: ${src_dir}/include/openssl/*.h"
    fi
    
    # 复制crypto头文件
    if ls "${src_dir}/include/crypto"/*.h 1> /dev/null 2>&1; then
        cp "${src_dir}/include/crypto"/*.h "${temp_pack_dir}/include/crypto/"
        info_msg "已复制所有crypto头文件"
    else
        warn_msg "警告: crypto头文件不存在: ${src_dir}/include/crypto/*.h"
    fi
    
    # 创建zip包
    info_msg "创建zip包: ${output_zip}"
    cd "${temp_pack_dir}" || { error_msg "无法进入handcake目录"; return 1; }
    zip -rq "../../../${output_zip}" . $redirect_flag || {
        error_msg "创建zip包失败"
        cd - > /dev/null || return 1
        return 1
    }
    cd - > /dev/null || return 1
    
    # 清理临时目录
    rm -rf "${temp_pack_dir}"
    
    info_msg "openssl ${openssl_version} 打包完成，生成文件: ${output_zip}"
    return 0
}

# 编译Lua 5.3.2库
# 依赖: wget, tar, 交叉编译工具链
compile_lua_5.3.2() {
    local lua_version="5.3.2"
    local lua_dir="lua-${lua_version}"
    local lua_tar="${lua_dir}.tar.gz"
    local lua_url="https://www.lua.org/ftp/${lua_tar}"

    # 检查是否已存在源码目录
    if [ ! -d "${lua_dir}" ]; then
        info_msg "Lua ${lua_version} 源码目录不存在，开始下载..."

        # 下载源码包
        if ! wget "${lua_url}" -O "${lua_tar}"; then
            error_msg "错误: 无法下载Lua源码包 ${lua_url}"
            return 1
        fi

        # 解压源码包
        info_msg "正在解压 ${lua_tar}..."
        if ! tar -zxvf "${lua_tar}"; then
            error_msg "错误: 无法解压 ${lua_tar}"
            rm -f "${lua_tar}"  # 清理下载失败的文件
            return 1
        fi

        # 清理压缩包
        rm -f "${lua_tar}"
    fi

    # 进入源码目录
    cd "${lua_dir}" || { error_msg "错误: 无法进入目录 ${lua_dir}"; return 1; }

    # 检查Makefile是否存在，如果存在则执行make clean
    if [ -f "Makefile" ]; then
        eval "make clean ${redirect_flag}" || { error_msg "Lua清理失败"; return 1; }
    fi

    # 检查交叉编译工具链
    local cc_path="${cross_chain}/bin/${target}-gcc"
    local cxx_path="${cross_chain}/bin/${target}-g++"
    if [ ! -x "${cc_path}" ] || [ ! -x "${cxx_path}" ]; then
        error_msg "错误: 交叉编译工具链不存在或不可执行"
        return 1
    fi

    # 设置环境变量
    export CC="${cc_path}"
    export CXX="${cxx_path}"

    # 编译源码
    info_msg "正在编译Lua ${lua_version}..."
    if ! make posix -j$(nproc) CC="${cc_path}" CXX="${cxx_path}" $redirect_flag; then
        error_msg "错误: Lua编译失败"
        return 1
    fi

    cd .. || return 1
    unset CC CXX
    info_msg "Lua ${lua_version} 编译成功"
    return 0
}

# 打包Lua 5.3.2库函数
# 生成的文件结构类似handcake/linux/lua-arm-openwrt-linux
# 最终生成的文件为lua-5.3.2-linux-${target}-1.zip
pack_lua_5.3.2() {
    local lua_version="5.3.2"
    local src_dir="lua-${lua_version}/src"
    local build_version="1"
    local output_zip="lua-${lua_version}-linux-${target}-${build_version}.zip"
    local temp_pack_dir="handcake/linux/lua-${target}"

    info_msg "开始打包Lua ${lua_version}..."

    # 检查目标路径参数
    if [ -z "${target}" ]; then
        error_msg "错误: 未指定target参数，无法执行打包操作"
        return 1
    fi

    # 检查源码目录是否存在
    if [ ! -d "${src_dir}" ]; then
        error_msg "错误: Lua源码目录不存在: ${src_dir}"
        return 1
    fi

    # 清理之前的打包文件
    rm -rf "${temp_pack_dir}" "${output_zip}"

    # 创建目标目录结构
    info_msg "创建打包目标目录结构: ${temp_pack_dir}"
    mkdir -p "${temp_pack_dir}/lib"
    mkdir -p "${temp_pack_dir}/include"

    # 复制库文件
    info_msg "复制库文件..."
    # 静态库
    if [ -f "${src_dir}/liblua.a" ]; then
        cp -f "${src_dir}/liblua.a" "${temp_pack_dir}/lib/"
        info_msg "已复制静态库: liblua.a"
    else
        error_msg "错误: 静态库文件不存在: ${src_dir}/liblua.a"
        return 1
    fi

    # 复制头文件
    info_msg "复制头文件..."
    local headers=("lua.h" "lualib.h" "lauxlib.h" "luaconf.h")
    for header in "${headers[@]}"; do
        if [ -f "${src_dir}/${header}" ]; then
            cp -f "${src_dir}/${header}" "${temp_pack_dir}/include/"
            info_msg "已复制头文件: ${header}"
        else
            warn_msg "警告: 头文件不存在: ${src_dir}/${header}"
        fi
    done

    # 创建zip包
    info_msg "创建zip包: ${output_zip}"
    cd "${temp_pack_dir}" || { error_msg "无法进入handcake目录"; return 1; }
    zip -rq "../../../${output_zip}" . $redirect_flag || {
        error_msg "创建zip包失败"
        cd - > /dev/null || return 1
        return 1
    }
    cd - > /dev/null || return 1

    # 清理临时目录
    rm -rf "${temp_pack_dir}"

    info_msg "Lua ${lua_version} 打包完成，生成文件: ${output_zip}"
    return 0
}


# 编译eudev 3.2.9库函数
compile_eudev_3.2.9() {
    local eudev_version="3.2.9"
    local eudev_dir="eudev-${eudev_version}"
    local eudev_tar="${eudev_dir}.tar.gz"
    local eudev_url="https://dev.gentoo.org/~blueness/eudev/${eudev_tar}"

    info_msg "开始编译eudev ${eudev_version}..."

    # 检查是否已存在源码目录
    if [ ! -d "${eudev_dir}" ]; then
        info_msg "eudev ${eudev_version} 源码目录不存在，开始下载..."

        # 下载源码包
        if ! wget "${eudev_url}" -O "${eudev_tar}"; then
            error_msg "错误: 无法下载eudev源码包 ${eudev_url}"
            return 1
        fi

        # 解压源码包
        info_msg "正在解压 ${eudev_tar}..."
        if ! tar -zxvf "${eudev_tar}"; then
            error_msg "错误: 无法解压 ${eudev_tar}"
            rm -f "${eudev_tar}"  # 清理下载失败的文件
            return 1
        fi

        # 清理压缩包
        rm -f "${eudev_tar}"
    fi

    # 进入源码目录
    cd "${eudev_dir}" || { error_msg "错误: 无法进入目录 ${eudev_dir}" ; return 1; }

    # 检查Makefile是否存在，如果存在则执行make clean
    if [ -f "Makefile" ]; then
        eval "make clean ${redirect_flag}" || { error_msg "eudev清理失败"; return 1; }
    fi

    # 检查交叉编译工具链
    local cc_path="${cross_chain}/bin/${target}-gcc"
    local cxx_path="${cross_chain}/bin/${target}-g++"
    if [ ! -x "${cc_path}" ] || [ ! -x "${cxx_path}" ]; then
        error_msg "错误: 交叉编译工具链不存在 ${cc_path} 或 ${cxx_path}"
        return 1
    fi

    # 配置编译选项
    info_msg "正在配置eudev ${eudev_version}..."
    if ! ./configure \
        --host="${target}" \
        CC="${cc_path}" \
        CXX="${cxx_path}" \
        --disable-kmod \
        --disable-blkid \
        --disable-selinux \
        $redirect_flag
    then
        error_msg "错误: eudev配置失败"
        return 1
    fi

    # 编译源码
    info_msg "正在编译eudev ${eudev_version}..."
    if ! make -j$(nproc) $redirect_flag; then
        error_msg "错误: eudev编译失败"
        return 1
    fi

    cd .. || return 1
    info_msg "eudev ${eudev_version} 编译成功"
    return 0
}

# 打包eudev 3.2.9库函数
# 依赖: 已编译的eudev库
pack_eudev_3.2.9() {
    local eudev_version="3.2.9"
    local build_version="1"
    local eudev_dir="eudev-${eudev_version}"
    local output_zip="eudev-${eudev_version}-linux-${target}-${build_version}.zip"
    local temp_pack_dir="handcake/linux/eudev-${target}"
    local base_dir="${eudev_dir}/src/libudev"
    local lib_dir="${base_dir}/.libs"

    info_msg "开始打包eudev ${eudev_version}..."

    # 检查源码目录是否存在
    if [ ! -d "${eudev_dir}" ]; then
        error_msg "eudev源码目录不存在: ${eudev_dir}"
        return 1
    fi

    # 检查编译产物是否存在
    if [ ! -d "${lib_dir}" ] || [ -z "$(ls -A ${lib_dir}/libudev.so* 2>/dev/null)" ]; then
        error_msg "eudev库文件不存在，请先编译: ${lib_dir}/libudev.so*"
        return 1
    fi

    # 创建临时打包目录
    rm -rf "${temp_pack_dir}"
    mkdir -p "${temp_pack_dir}/bin" || { error_msg "创建临时打包目录失败"; return 1; }

    # 复制库文件
    cp -f ${lib_dir}/libudev.so* "${temp_pack_dir}/bin/" || {
        error_msg "复制eudev动态库失败"
        return 1
    }

    mkdir -p "${temp_pack_dir}/include" || { error_msg "创建临时打包目录失败"; return 1; }
    cp -f ${base_dir}/libudev.h "${temp_pack_dir}/include/" || {
        error_msg "复制eudev头文件失败"
        return 1
    }

    # 创建zip包
    cd "${temp_pack_dir}" || { error_msg "无法进入handcake目录"; return 1; }
    zip -rq "../../../${output_zip}" . $redirect_flag || {
        error_msg "创建zip包失败"
        cd - > /dev/null || return 1
        return 1
    }
    cd - > /dev/null || return 1

    # 清理临时目录
    rm -rf "${temp_pack_dir}"

    info_msg "eudev ${eudev_version} 打包完成，生成文件: ${output_zip}"
    return 0
}

compile_uci() {
    local libubox_dir="libubox"
    local libubox_repo_url="https://git.openwrt.org/project/libubox.git"
    local uci_dir="uci"
    local uci_repo_url="https://git.openwrt.org/project/uci.git"

    info_msg "开始编译uci，首先编译libubox..."

    # 检查编译机上是否安装了json-c开发库
    info_msg "检查编译机上是否安装了json-c开发库..."
    if ! pkg-config --exists json-c; then
        error_msg "未找到json-c开发库，需要安装"

        # 检查是否为Ubuntu系统
        if [ -f /etc/lsb-release ] && grep -q "Ubuntu" /etc/lsb-release; then
            info_msg "检测到Ubuntu系统，尝试安装libjson-c-dev..."
            sudo apt-get update && sudo apt-get install -y libjson-c-dev || {
                error_msg "安装libjson-c-dev失败，请手动安装"
                return 1
            }
        else
            error_msg "当前不是Ubuntu系统，请手动安装json-c开发库"
            return 1
        fi
    else
        info_msg "已检测到json-c开发库"
    fi

    # 编译libubox库
    info_msg "开始编译libubox..."

    # 检查libubox目录是否存在，如果不存在则克隆仓库
    if [ ! -d "${libubox_dir}" ]; then
        info_msg "从${libubox_repo_url}克隆libubox仓库..."
        git clone ${libubox_repo_url} ${libubox_dir} || { error_msg "libubox仓库克隆失败"; return 1; }
    fi

    # 进入libubox源码目录
    cd ${libubox_dir} || { error_msg "无法进入${libubox_dir}目录"; return 1; }

    # 修改CMakeLists.txt文件
    info_msg "修改libubox的CMakeLists.txt文件..."

    # 注释掉ADD_SUBDIRECTORY(lua)和ADD_SUBDIRECTORY(examples)
    sed -i '48s/^/#/' CMakeLists.txt || { error_msg "注释ADD_SUBDIRECTORY(lua)失败"; cd - > /dev/null || return 1; return 1; }
    sed -i '49s/^/#/' CMakeLists.txt || { error_msg "注释ADD_SUBDIRECTORY(examples)失败"; cd - > /dev/null || return 1; return 1; }

    # 检查Makefile是否存在，如果存在则执行make clean
    if [ -f "Makefile" ]; then
        eval "make clean ${redirect_flag}" || { error_msg "libubox清理失败"; cd - > /dev/null || return 1; return 1; }
    fi

    # 执行cmake配置，设置交叉编译器路径
    info_msg "配置libubox cmake交叉编译环境..."
    cmake -DCMAKE_C_COMPILER=${cross_chain}/bin/${target}-gcc . || {
        error_msg "libubox cmake配置失败";
        cd - > /dev/null || return 1;
        return 1;
    }

    # 执行make编译
    info_msg "开始编译libubox..."
    if ! make -j$(nproc) $redirect_flag; then
        error_msg "libubox编译失败"
        cd - > /dev/null || return 1
        return 1
    fi

    info_msg "libubox编译完成"
    cd - > /dev/null || return 1  # 返回原目录

    # 编译uci库
    info_msg "开始编译uci..."

    # 检查uci目录是否存在，如果不存在则克隆仓库
    if [ ! -d "${uci_dir}" ]; then
        info_msg "从${uci_repo_url}克隆uci仓库..."
        git clone ${uci_repo_url} ${uci_dir} || { error_msg "uci仓库克隆失败"; return 1; }
    fi

    # 进入uci源码目录
    cd ${uci_dir} || { error_msg "无法进入${uci_dir}目录"; return 1; }

    # 注释掉一些不需要的功能
    sed -i '47s/^/#/' CMakeLists.txt || { error_msg "注释ADD_EXECUTABLE(cli cli.c)失败"; cd - > /dev/null || return 1; return 1; }
    sed -i '48s/^/#/' CMakeLists.txt || { error_msg "注释SET_TARGET_PROPERTIES(cli PROPERTIES OUTPUT_NAME uci)失败"; cd - > /dev/null || return 1; return 1; }
    sed -i '50s/^/#/' CMakeLists.txt || { error_msg "注释TARGET_LINK_LIBRARIES(cli uci-static ubox-static)失败"; cd - > /dev/null || return 1; return 1; }
    sed -i '52s/^/#/' CMakeLists.txt || { error_msg "注释TARGET_LINK_LIBRARIES(cli uci ubox)失败"; cd - > /dev/null || return 1; return 1; }
    sed -i '58s/^/#/' CMakeLists.txt || { error_msg "注释ADD_SUBDIRECTORY(lua)失败"; cd - > /dev/null || return 1; return 1; }

    sed -i '85s/^/#/' CMakeLists.txt || { error_msg "注释INSTALL 85失败"; cd - > /dev/null || return 1; return 1; }
    sed -i '86s/^/#/' CMakeLists.txt || { error_msg "注释INSTALL 86失败"; cd - > /dev/null || return 1; return 1; }
    sed -i '87s/^/#/' CMakeLists.txt || { error_msg "注释INSTALL 87失败"; cd - > /dev/null || return 1; return 1; }
    sed -i '88s/^/#/' CMakeLists.txt || { error_msg "注释INSTALL 88失败"; cd - > /dev/null || return 1; return 1; }
    sed -i '89s/^/#/' CMakeLists.txt || { error_msg "注释INSTALL 89失败"; cd - > /dev/null || return 1; return 1; }

    # 检查Makefile是否存在，如果存在则执行make clean
    if [ -f "Makefile" ]; then
        eval "make clean ${redirect_flag}" || { error_msg "uci清理失败"; cd - > /dev/null || return 1; return 1; }
    fi

    # 设置PKG_CONFIG_PATH以找到libubox
    export PKG_CONFIG_PATH="../${libubox_dir}:$PKG_CONFIG_PATH"

    # 执行cmake配置，设置交叉编译器路径
    info_msg "配置uci cmake交叉编译环境..."
    cmake -DCMAKE_C_COMPILER=${cross_chain}/bin/${target}-gcc -Dubox_include_dir=.. -Dubox=../libubox . || {
        error_msg "uci cmake配置失败";
        cd - > /dev/null || return 1;
        return 1;
    }

    # 执行make编译
    info_msg "开始编译uci..."
    if ! make -j$(nproc) $redirect_flag; then
        error_msg "uci编译失败"
        cd - > /dev/null || return 1
        return 1
    fi

    info_msg "uci编译完成"
    cd - > /dev/null || return 1  # 返回原目录

    return 0
}



pack_uci() {
    local uci_version="1.0.0"
    local build_version="1"
    local libubox_dir="libubox"
    local uci_dir="uci"
    local output_zip="uci-${uci_version}-linux-${target}-${build_version}.zip"
    local temp_pack_dir="handcake/linux/uci-${target}"

    info_msg "开始打包uci ${uci_version}和libubox..."

    # 检查源码目录是否存在
    if [ ! -d "${libubox_dir}" ]; then
        error_msg "libubox源码目录不存在: ${libubox_dir}"
        return 1
    fi

    if [ ! -d "${uci_dir}" ]; then
        error_msg "uci源码目录不存在: ${uci_dir}"
        return 1
    fi

    # 检查编译产物是否存在
    if [ -z "$(ls -A ${libubox_dir}/libubox.so* 2>/dev/null)" ]; then
        error_msg "libubox库文件不存在，请先编译: ${libubox_dir}/libubox.so*"
        return 1
    fi

    if [ -z "$(ls -A ${uci_dir}/libuci.so* 2>/dev/null)" ]; then
        error_msg "uci库文件不存在，请先编译: ${uci_dir}/libuci.so*"
        return 1
    fi

    # 创建临时打包目录
    rm -rf "${temp_pack_dir}"
    mkdir -p "${temp_pack_dir}/bin" || { error_msg "创建临时打包目录失败"; return 1; }

    # 复制libubox库文件
    cp -f ${libubox_dir}/libubox.so "${temp_pack_dir}/bin/libubox.so.20210516" || {
        error_msg "复制libubox动态库失败"
        return 1
    }

    # 复制uci库文件
    cp -f ${uci_dir}/libuci.so* "${temp_pack_dir}/bin/" || {
        error_msg "复制uci动态库失败"
        return 1
    }

    # 创建zip包
    cd "${temp_pack_dir}" || { error_msg "无法进入handcake目录"; return 1; }
    zip -rq "../../../${output_zip}" . $redirect_flag || {
        error_msg "创建zip包失败"
        cd - > /dev/null || return 1
        return 1
    }
    cd - > /dev/null || return 1

    # 清理临时目录
    rm -rf "${temp_pack_dir}"

    info_msg "uci ${uci_version} 和 libubox 打包完成，生成文件: ${output_zip}"
    return 0
}
################# compile control #################
# 检查是否需要编译指定库
should_compile_3rd() {
    local lib="$1"
    if [ -z "$third_libs" ]; then
        return 0
    fi
    echo "$third_libs" | grep -q "$lib"
}

# 第三方库编译打包与上传函数
compile_3rd() {
    local exit_code=0

    if [ -n "$third_libs" ]; then
        info_msg "开始编译指定第三方依赖库: $third_libs ..."
    else
        info_msg "开始编译所有第三方依赖库..."
    fi

    # 按顺序执行各第三方库编译函数
    if should_compile_3rd "openssl"; then
        info_msg "编译openssl 1.1.1q..."
        compile_openssl_1.1.1q || { error_msg "openssl编译失败" ; exit_code=1; }
        pack_openssl_1.1.1q || { error_msg "openssl打包失败" ; exit_code=1; }
        $upload_flag && upload_modules "3rd" "openssl" "1.1.1q" "1"
    fi

    if should_compile_3rd "fftw"; then
        info_msg "编译fftw 3.3.10..."
        compile_fftw_3.3.10 || { error_msg "fftw编译失败" ; exit_code=1; }
        pack_fftw_3.3.10 || { error_msg "fftw打包失败" ; exit_code=1; }
        $upload_flag && upload_modules "3rd" "fftw" "3.3.10" "1"
    fi

    if should_compile_3rd "protobuf"; then
        info_msg "编译protobuf 3.15.8..."
        compile_protobuf_3.15.8 || { error_msg "protobuf编译失败" ; exit_code=1; }
        pack_protobuf_3.15.8 || { error_msg "protobuf打包失败" ; exit_code=1; }
        $upload_flag && upload_modules "3rd" "protobuf" "3.15.8" "1"
    fi

    if should_compile_3rd "zlib"; then
        info_msg "编译zlib 1.2.3..."
        compile_zlib_1.2.3 || { error_msg "zlib编译失败" ; exit_code=1; }
        pack_zlib_1.2.3 || { error_msg "zlib打包失败" ; exit_code=1; }
        $upload_flag && upload_modules "3rd" "zlib" "1.2.3" "1"
    fi

    if should_compile_3rd "replxx"; then
        info_msg "编译replxx 0.0.4..."
        compile_replxx_0.0.4 || { error_msg "replxx编译失败" ; exit_code=1; }
        pack_replxx_0.0.4 || { error_msg "replxx打包失败" ; exit_code=1; }
        $upload_flag && upload_modules "3rd" "replxx" "0.0.4" "1"
    fi

    if should_compile_3rd "lua"; then
        info_msg "编译Lua 5.3.2..."
        compile_lua_5.3.2 || { error_msg "Lua编译失败" ; exit_code=1; }
        pack_lua_5.3.2 || { error_msg "Lua打包失败" ; exit_code=1; }
        $upload_flag && upload_modules "3rd" "lua" "5.3.2" "1"
    fi

    if should_compile_3rd "eudev"; then
        info_msg "编译eudev 3.2.9..."
        compile_eudev_3.2.9 || { error_msg "eudev编译失败" ; exit_code=1; }
        pack_eudev_3.2.9 || { error_msg "eudev打包失败" ; exit_code=1; }
        $upload_flag && upload_modules "3rd" "eudev" "3.2.9" "1"
    fi

    if should_compile_3rd "uci"; then
        info_msg "编译uci"
        compile_uci || { error_msg "uci编译失败" ; exit_code=1; }
        pack_uci || { error_msg "uci打包失败" ; exit_code=1; }
        $upload_flag && upload_modules "3rd" "uci" "1.0.0" "1"
    fi

    if [ $exit_code -eq 0 ]; then
        info_msg "所有第三方库编译完成"
    else
        error_msg "部分第三方库编译失败，请检查错误信息"
        exit $exit_code
    fi
}

# 适用于main中的依赖(只编译需要的头文件依赖,具体没有用到库,所以只需要备份一份目标架构的包)
copy_sl_other_no_compile_module() {
    # 1. 检查jq是否安装，如果没有则安装
    check_jq_installation() {
        if ! command -v jq &> /dev/null; then
            info_msg "jq 工具未安装，正在尝试安装..."
            if [ -f "/etc/debian_version" ]; then
                sudo apt-get update && sudo apt-get install -y jq || {
                    error_msg "在Debian/Ubuntu系统上安装jq失败，请手动安装后重试"
                    return 1
                }
            elif [ -f "/etc/redhat-release" ]; then
                sudo yum install -y jq || {
                    error_msg "在RedHat/CentOS系统上安装jq失败，请手动安装后重试"
                    return 1
                }
            else
                error_msg "不支持的系统类型，无法自动安装jq，请手动安装后重试"
                return 1
            fi
            info_msg "jq 工具安装成功"
        else
            info_msg "jq 工具已安装"
        fi
        return 0
    }

    # 3. 通用模块处理函数，参数为模块名称
    process_module() {
        local module_owner="$1"
        local module_name="$2"
        local module_version="$3"
        local build_version="$4"

        if [ -z "$module_name" ]; then
            error_msg "未提供模块名称参数"
            return 1
        fi

        local module_dir="handcake/linux/${module_name}-${target}"

        # 检查本地是否存在模块目录
        if [ -d "$module_dir" ]; then
            warn_msg "${module_name}目录已存在: $module_dir"
            return 0
        fi

        local base_url="http://devres.oray.net/oraylibs/${module_owner}/${module_name}"

        # 根据模块名称设置相应的版本和默认架构
        local fallback_arch="arm-openwrt-linux"

        local target_filename="${module_name}-${module_version}-linux-${target}-${build_version}.zip"

        # 使用curl -I探测目标URL是否存在
        info_msg "正在探测${module_name}目标文件是否存在: ${base_url}/${target_filename}"
        local http_status=$(curl -s -o /dev/null -w "%{http_code}" -I "${base_url}/${target_filename}")

        local download_url="${base_url}/${target_filename}"
        local local_filename="${target_filename}"

        # 如果目标文件不存在，使用fallback架构
        if [ "$http_status" -ne 200 ]; then
            info_msg "目标文件不存在 (HTTP状态码: $http_status)，尝试使用fallback架构: $fallback_arch"
            fallback_filename="${module_name}-${module_version}-linux-${fallback_arch}-${build_version}.zip"
            fallback_download_url="${base_url}/${fallback_filename}"

            # 再次探测fallback文件是否存在
            fallback_status=$(curl -s -o /dev/null -w "%{http_code}" -I "$fallback_download_url")
            if [ "$fallback_status" -ne 200 ]; then
                error_msg "fallback文件也不存在 (HTTP状态码: $fallback_status): $fallback_download_url"
                return 1
            fi

            # 下载文件
            info_msg "正在下载${module_name}文件: $fallback_download_url"
            curl -o "$fallback_filename" "$fallback_download_url" || {
                error_msg "下载${module_name}文件失败"
                return 1
            }

            mv "$fallback_filename" "$local_filename"
            # 上传文件
            curl -F "file=@$local_filename" "${base_url}/" || {
                error_msg "上传${module_name}文件失败"
                rm -f "$local_filename"
                return 1
            }
        else
            # 下载文件
            warn_msg "目标文件已存在 (HTTP状态码: $http_status)"
        fi

        return 0
    }

    ## just do test
    # process_module "sunlogin" "sl-codec" "1.0.2" "8b2926f5"
    # return 0

    # 主执行逻辑
    check_jq_installation || return 1

    sl_sunlogin_modules="sl-control-desktop sl-control-file sl-control-ssh sl-control-usbip sl-control-camera sl-codec sl-net-p2p"
    sl_3rd_modules="SDL2 SDL2_ttf"
    # 定义json_file路径（项目根目录下的modules.json）
    json_file="$(pwd)/modules.json"

    # 检查modules.json文件是否存在
    if [ ! -f "$json_file" ]; then
        error_msg "modules.json文件不存在: $json_file"
        return 1
    fi

    # 读取json文件内容
    json_data=$(jq '.' "$json_file") || {
        error_msg "读取modules.json文件失败"
        return 1
    }

  # 处理sl_sunlogin_modules中的模块
    for module_name in $sl_sunlogin_modules; do
        # 从modules.json中提取模块信息
        # 对于sunlogin模块，module_owner为"sunlogin"
        module_owner="sunlogin"

        # 首先尝试找到包含linux-${target}的build_version的模块条目
        # 这解决了同名模块多个条目的问题
        module_entry=$(echo "$json_data" | jq -r ".modules[] | select(.name == \"${module_name}\" and .build_version | has(\"linux-${target}\"))" 2>/dev/null)

        if [ -n "$module_entry" ] && [ "$module_entry" != "null" ]; then
            # 从找到的条目中提取版本信息
            module_version=$(echo "$module_entry" | jq -r ".version")
            build_version=$(echo "$module_entry" | jq -r ".build_version[\"linux-${target}\"]")
        else
            # 如果没有找到特定平台的条目，尝试提取任意版本
            module_version=$(echo "$json_data" | jq -r ".modules[] | select(.name == \"${module_name}\") | .version" 2>/dev/null | head -n 1)
            build_version=$(echo "$json_data" | jq -r ".modules[] | select(.name == \"${module_name}\") | .build_version | to_entries[0].value" 2>/dev/null | head -n 1)
        fi

        # 如果未找到版本信息，使用默认值
        if [ -z "$module_version" ] || [ "$module_version" = "null" ]; then
            warn_msg "未找到模块${module_name}的版本信息，使用默认版本1.0.0"
            module_version="1.0.0"
        fi

        # 如果未找到build_version信息，使用默认值
        if [ -z "$build_version" ] || [ "$build_version" = "null" ]; then
            warn_msg "未找到模块${module_name}的build_version信息，使用默认版本1"
            build_version="1"
        fi

        info_msg "处理向日葵模块: ${module_name}, 版本: ${module_version}, build版本: ${build_version}"
        process_module "$module_owner" "$module_name" "$module_version" "$build_version" || {
            error_msg "处理模块${module_name}失败"
            return 1
        }
    done

    # 处理sl_3rd_modules中的模块
    for module_name in $sl_3rd_modules; do
        # 从modules.json中提取模块信息
        # 对于3rd模块，module_owner为"3rd"
        module_owner="3rd"

        # 同样处理第三方模块的多个条目情况
        module_entry=$(echo "$json_data" | jq -r ".modules[] | select(.name == \"${module_name}\" and .build_version | has(\"linux-${target}\"))" 2>/dev/null)

        if [ -n "$module_entry" ] && [ "$module_entry" != "null" ]; then
            # 从找到的条目中提取版本信息
            module_version=$(echo "$module_entry" | jq -r ".version")
            build_version=$(echo "$module_entry" | jq -r ".build_version[\"linux-${target}\"]")
        else
            # 如果没有找到特定平台的条目，尝试提取任意版本
            module_version=$(echo "$json_data" | jq -r ".modules[] | select(.name == \"${module_name}\") | .version" 2>/dev/null | head -n 1)
            build_version=$(echo "$json_data" | jq -r ".modules[] | select(.name == \"${module_name}\") | .build_version | to_entries[0].value" 2>/dev/null | head -n 1)
        fi

        # 如果未找到版本信息，使用默认值
        if [ -z "$module_version" ] || [ "$module_version" = "null" ]; then
            warn_msg "未找到模块${module_name}的版本信息，使用默认版本1.0.0"
            module_version="1.0.0"
        fi

        # 如果未找到build_version信息，使用默认值
        if [ -z "$build_version" ] || [ "$build_version" = "null" ]; then
            warn_msg "未找到模块${module_name}的build_version信息，使用默认版本1"
            build_version="1"
        fi

        info_msg "处理第三方模块: ${module_name}, 版本: ${module_version}, build版本: ${build_version}"
        process_module "$module_owner" "$module_name" "$module_version" "$build_version" || {
            error_msg "处理模块${module_name}失败"
            return 1
        }
    done

    return 0
}
################################################# 

################# upload control #################
# 上传模块文件到服务器, 注意向日葵插件是可以不用这个上传的(其编译脚本有-r参数,可用于上传), 这个可用于上传3rd的库
# 参数:
#   $1 - 模块所属（模块所有者标识）
#   $2 - 模块名（基础模块名称）
#   $3 - 模块版本（）
#   $4 - 编译版本（有git填git commitid）
upload_modules() {
    local url="http://devres.oray.net"
    local module_owner="$1"
    local module_name="$2"
    local module_ver="$3"
    local build_ver="$4"
    filename="${module_name}-${module_ver}-linux-${target}-${build_ver}.zip"

    # 检查文件是否存在
    if [ ! -f "$filename" ]; then
        error_msg "Error: Module file not found - $filename" 
        return 1
    fi

    info_msg "Starting upload of $filename url: ${url}/oraylibs/${module_owner}/${module_name}/${filename}" 
    
    curl -F "file=@$filename" "${url}/oraylibs/${module_owner}/${module_name}/" || {
        error_msg "Error: Failed to uploaded $filename" 
        return 1
    }
    info_msg "Upload of $filename completed" 
    return 0
}
################################################# 


################# pack control #################
# 打包编译产物函数
# 方便放到openwrt sunlogin-client-new 组件下直接替换二进制
# sunlogin-client-new Makefile中会根据当前项目选择对应交叉编译器的二进制进行安装
#
# 最终打包目录结构: 
# arm-openwrt-linux/
# └── usr
#     └── sbin
#         ├── plugins
#         │   ├── libaudioctrl.so
#         │   ├── libvideoctrl_camera.so
#         │   ├── libvideoctrl.so
#         │   ├── sl-client-audio.so
#         │   ├── sl-client-camera.so
#         │   ├── sl-client-desktop.so
#         │   ├── sl-client-file.so
#         │   ├── sl-client-ssh.so
#         │   └── sl-client-usbip.so
#         ├── sunloginclient
#         └── sunloginclient_desktop

pack_all() {
    # 检查目标路径参数
    if [ -z "${target}" ]; then
        error_msg "错误: 未指定target参数，无法执行打包操作"
        exit 1
    fi

    # 进入项目根目录
    cd "$project_root" || { error_msg "无法进入项目根目录: $project_root"; exit 1; }

    # 创建目标目录结构
    info_msg "创建打包目标目录结构..."
    mkdir -p "${target}/usr/sbin" || { error_msg "创建sbin目录失败" ; exit 1; }
    mkdir -p "${target}/usr/sbin/plugins" || { error_msg "创建plugins目录失败" ; exit 1; }

    # 打包主程序文件
    info_msg "开始打包主程序文件..."
    [ -f "$project_root/build/sunloginclient" ] && cp "$project_root/build/sunloginclient" "${target}/usr/sbin/" || error_msg "警告: sunloginclient主程序不存在"
    [ -f "$project_root/build/sunloginclient_desktop" ] && cp "$project_root/build/sunloginclient_desktop" "${target}/usr/sbin/" || error_msg "警告: sunloginclient_desktop主程序不存在"

    # 打包模块插件文件
    info_msg "开始打包模块插件..."
    if [ -n "${modules}" ]; then
        local modules_array=(${modules})
        for module in "${modules_array[@]}"; do
            local so_path="$project_root/modules/client/${module}/build/sl-client-${module}.so"
            if [ -f "${so_path}" ]; then
                cp "${so_path}" "${target}/usr/sbin/plugins/"
                info_msg "已打包模块: ${module}"
            else
                warn_msg "警告: 模块${module}的so文件不存在: ${so_path}"
            fi
        done
    else
        warn_msg "警告: 未指定任何模块，跳过模块打包"
    fi

    # 打包视频控制库
    info_msg "开始打包视频控制库..."
    local videoctrl_lib="$project_root/kk_sunlogin_upgrade/_install/lib/libvideoctrl.so"
    if [ -f "${videoctrl_lib}" ]; then
        cp "${videoctrl_lib}" "${target}/usr/sbin/plugins/"
        info_msg "已打包视频控制库: libvideoctrl.so"
    else
        warn_msg "警告: 视频控制库不存在: ${videoctrl_lib}"
    fi

    # 添加libvideoctrl_camera.so的打包
    local videoctrl_camera_lib="$project_root/kk_sunlogin_upgrade/_install/lib/libvideoctrl_camera.so"
    if [ -f "${videoctrl_camera_lib}" ]; then
        cp "${videoctrl_camera_lib}" "${target}/usr/sbin/plugins/"
        info_msg "已打包视频控制库: libvideoctrl_camera.so"
    else
        warn_msg "警告: 视频控制库不存在: ${videoctrl_camera_lib}"
    fi

    # 打包音频控制库
    info_msg "开始打包音频控制库..."
    local audioctrl_lib="$project_root/kk_sunlogin_upgrade/_install/lib/libaudioctrl.so"
    if [ -f "${audioctrl_lib}" ]; then
        cp "${audioctrl_lib}" "${target}/usr/sbin/plugins/"
        info_msg "已打包音频控制库: libaudioctrl.so" 
    else
        warn_msg "警告: 音频控制库不存在: ${audioctrl_lib}" 
    fi

    info_msg "所有打包操作已完成" 
}
################################################# 


# ==============================================
# 脚本参数解析（全局参数）
# ==============================================
cross_chain=""
target=""
modules=""
debug_mode=false
modules_specified=false

# build options
build_modules=false
build_main=false
build_3rd=false
third_libs=""
pack_only=false
verbose_mode=false
redirect_flag=""
default_modules="desktop audio usbip ssh camera file kk"
#default_modules="audio usbip ssh camera file"
#default_modules="camera file"

[ $# -eq 0 ] && { print_help; exit 0; }

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cross_chain)
            cross_chain="$2"
            shift 2
            ;;
        --target)
            target="$2"
            shift 2
            ;;
        --modules)
            modules="$2"
            modules_specified=true
            build_modules=true
            shift 2
            ;;
        --main)
            build_main=true
            shift
            ;;
        --debug)
            debug_mode=true
            shift
            ;;
        --pack)
            pack_only=true
            shift
            ;;
        --quiet)
            verbose_mode=true
            shift
            ;;
        --3rd)
            build_3rd=true
            third_libs="$2"
            if [[ "$2" == --* ]] || [ -z "$2" ]; then
                third_libs=""
            else
                shift
            fi
            shift
            ;;
        --no-upload)
            no_upload=true
            shift
            ;;
        --module_path)
            local module_name="$2"
            local module_path="$3"
            if [ -z "$module_name" ] || [ -z "$module_path" ]; then
                error_msg "错误: --module_path 需要两个参数: <module_name> <path>"
                exit 1
            fi
            module_paths["$module_name"]="$module_path"
            shift 3
            ;;
        --project_root)
            project_root="$2"
            shift 2
            ;;
        --help)
            print_help
            exit 0
            ;;
        *)
            error_msg "未知参数: $1"
            print_help
            exit 1
            ;;
    esac

done

# 如果未指定 project_root，默认使用当前目录
if [ -z "$project_root" ]; then
    project_root="$(pwd)"
fi

# 检查必要参数
if [ -z "$cross_chain" ] || [ -z "$target" ]; then
    error_msg "错误: --cross_chain和--target参数必须设置" 
    exit 1
fi


if [ "$verbose_mode" = true ]; then
    redirect_flag="> /dev/null 2>&1"
fi

########################## just do some test ##########################
# compile_fftw_3.3.10
# pack_fftw_3.3.10
# upload_modules "3rd" "fftw" "3.3.10" "1"

# compile_zlib_1.2.3
# pack_zlib_1.2.3
# upload_modules "3rd" "zlib" "1.2.3" "1"

# compile_protobuf_3.15.8
# pack_protobuf_3.15.8
# upload_modules "3rd" "protobuf" "3.15.8" "1"

# compile_replxx_0.0.4
# pack_replxx_0.0.4
# upload_modules "3rd" "replxx" "0.0.4" "1"

# compile_openssl_1.1.1q
# pack_openssl_1.1.1q
# upload_modules "3rd" "openssl" "1.1.1q" "1"

# compile_lua_5.3.2
# pack_lua_5.3.2
# upload_modules "3rd" "lua" "5.3.2" "1"

# compile_eudev_3.2.9
# pack_eudev_3.2.9
# upload_modules "3rd" "eudev" "3.2.9" "1"

# compile_uci
# pack_uci
# upload_modules "3rd" "uci" "1.0.0" "1"

# compile_3rd

## modules="file"
# modules=${modules:-$default_modules}
# compile_modules "$modules"

# copy_sl_other_no_compile_module

# exit 0
###################################################################

# 仅打包编译产物, 不进行编译(默认是已经编译好了)
if [ "$pack_only" = true ]; then
    info_msg "开始打包编译产物..." 
    modules=${modules:-$default_modules}
    pack_all
    info_msg "打包编译产物完成" 
    exit 0
fi

# 执行编译逻辑
if "$build_modules" || "$build_main" || "$build_3rd"; then
    $build_3rd && compile_3rd
    $build_modules && compile_modules "$modules"
    $build_main && compile_main
else
    # compile_3rd
    # copy_sl_other_no_compile_module
    modules=$default_modules
    compile_modules "$modules"
    # compile_main
fi

info_msg "开始打包编译产物..." 
pack_all
info_msg "打包编译产物完成" 
