# jemalloc-5.3.0 QNX 交叉编译指南

本文档提供了 jemalloc-5.3.0 在 QNX 平台上的交叉编译完整指南。

## 目录结构

```
.
├── jemalloc-5.3.0.tar.bz2          # 原始源码包
├── patches/
│   └── jemalloc-5.3.0-qnx.patch    # QNX 适配补丁
├── build_qnx.sh                     # 一键编译脚本
└── README.md                        # 本文档
```

## 环境要求

- **QNX SDP 8.0** 或更高版本
- **Linux 主机** (用于交叉编译)
- 已配置 QNX 环境变量 (`QNX_SDP`, `QNX_HOST`, `QNX_TARGET`)

## 快速开始

### 1. 解压源码

```bash
tar xf jemalloc-5.3.0.tar.bz2
cd jemalloc-5.3.0
```

### 2. 应用 QNX 补丁

```bash
patch -p1 < ../patches/jemalloc-5.3.0-qnx.patch
```

预期输出：
```
patching file configure
patching file configure.ac
patching file include/jemalloc/internal/jemalloc_internal_decls.h
patching file include/jemalloc/internal/jemalloc_internal_defs.h.in
patching file src/background_thread.c
patching file src/pages.c
```

### 3. 编译

```bash
../build_qnx.sh aarch64le    # ARM 64-bit
# 或
../build_qnx.sh x86_64       # x86 64-bit
```

### 4. 编译输出

编译完成后，输出目录结构如下：

```
install-qnx-aarch64le/
├── lib/
│   ├── libjemalloc.so       # 符号链接
│   └── libjemalloc.so.2     # 动态库 (ARM aarch64)
└── include/jemalloc/
    ├── jemalloc.h
    ├── jemalloc_defs.h
    ├── jemalloc_macros.h
    ├── jemalloc_mangle.h
    ├── jemalloc_protos.h
    ├── jemalloc_rename.h
    ├── jemalloc_typedefs.h
    └── internal/
        └── ...
```

## 补丁说明

本补丁对 jemalloc-5.3.0 进行以下修改：

| 文件 | 修改内容 |
|------|----------|
| `configure.ac` | 添加 QNX 系统检测 (`nto*-*`) |
| `configure` | 自动定义 `JEMALLOC_OS_QNX` 宏 |
| `include/jemalloc/internal/jemalloc_internal_defs.h.in` | 添加 `_QNX_SOURCE` 和 `_POSIX_C_SOURCE` 定义 |
| `include/jemalloc/internal/jemalloc_internal_decls.h` | 排除 QNX 不支持的 `<sys/syscall.h>` |
| `src/pages.c` | 使用 `posix_memalign()` 替代 `mmap()` 实现内存分配 |
| `src/background_thread.c` | 跳过 QNX 不支持的 `pthread_setaffinity_np()` |

## 在 QNX 目标上使用

### 方法一：设置环境变量

```bash
export LD_LIBRARY_PATH=/path/to/lib:$LD_LIBRARY_PATH
```

### 方法二：编译时链接

```bash
qcc -Vgcc_ntoaarch64le \
    -I/path/to/include/jemalloc \
    -L/path/to/lib \
    -ljemalloc \
    -o myapp myapp.c
```

### 方法三：使用 `je_` 前缀 API

```c
#include <stdio.h>
#include <jemalloc.h>

int main() {
    void *ptr = je_malloc(1024);
    if (ptr) {
        printf("Allocated: %p\n", ptr);
        je_free(ptr);
    }
    return 0;
}
```

## 编译选项说明

`build_qnx.sh` 脚本默认使用以下配置选项：

| 选项 | 说明 |
|------|------|
| `--with-lg-page=12` | 页面大小 4KB (2^12) |
| `--disable-static` | 禁用静态库 |
| `--enable-shared` | 启用动态库 |
| `--disable-fill` | 禁用内存填充功能 |
| `--disable-utrace` | 禁用 utrace 跟踪 |
| `--disable-stats` | 禁用统计功能 |
| `--disable-debug` | 禁用调试模式 |
| `--disable-cxx` | 禁用 C++ 支持 |

如需自定义选项，可修改 `build_qnx.sh` 脚本中的 `configure` 参数。

## 手动编译（可选）

如果需要更精细的控制，可以手动执行以下步骤：

```bash
# 1. 设置 QNX 环境
source ~/qnx800/qnxsdp-env.sh

# 2. 设置目标架构
export TARGET_ARCH=aarch64le
export QCC_TARGET=gcc_ntoaarch64le

# 3. 配置
./configure \
    --host=aarch64-unknown-linux-gnu \
    CC="qcc -V${QCC_TARGET}" \
    CXX="q++ -V${QCC_TARGET}" \
    CFLAGS="-DJEMALLOC_OS_QNX -D_QNX_SOURCE -D_POSIX_C_SOURCE=200809L -O2" \
    --with-lg-page=12 \
    --disable-static \
    --enable-shared \
    --prefix=$(pwd)/install-qnx-${TARGET_ARCH}

# 4. 编译
make -j$(nproc)

# 5. 安装
make install
```

## 故障排除

### 问题：`qcc: command not found`

**解决方案**：确保已 source QNX 环境脚本：
```bash
source ~/qnx800/qnxsdp-env.sh
```

### 问题：`JEMALLOC_OS_QNX` 未定义

**解决方案**：确保已正确应用补丁，并在 CFLAGS 中包含：
```bash
CFLAGS="-DJEMALLOC_OS_QNX -D_QNX_SOURCE -D_POSIX_C_SOURCE=200809L"
```

### 问题：链接时找不到 `-lpthread`

**解决方案**：QNX 的 pthread 已集成在 libc 中，无需单独链接。移除 `-lpthread` 参数。

