#!/bin/bash
# 上下文注入 Hook 演示脚本
# 展示 DevBooks 自动上下文注入的完整效果

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/hooks/context-inject-global.sh"

# 检查 hook 是否存在
if [ ! -f "$HOOK_SCRIPT" ]; then
    echo -e "${RED}错误: 找不到 hook 脚本: $HOOK_SCRIPT${NC}"
    exit 1
fi

# 打印分隔线
print_separator() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 打印标题
print_title() {
    echo ""
    print_separator
    echo -e "${BOLD}${MAGENTA}$1${NC}"
    print_separator
    echo ""
}

# 打印子标题
print_subtitle() {
    echo -e "${BOLD}${BLUE}▶ $1${NC}"
    echo ""
}

# 打印提示
print_prompt() {
    echo -e "${YELLOW}💬 用户提示:${NC} ${BOLD}$1${NC}"
    echo ""
}

# 打印 JSON 输出（美化）
print_json() {
    echo "$1" | jq -C '.' 2>/dev/null || echo "$1"
}

# 演示 1: 基础意图分析
demo_intent_analysis() {
    print_title "演示 1: 四维意图分析 (4D Intent Analysis)"

    local prompts=(
        "fix the authentication bug in login function"
        "add a new feature to export data to CSV"
        "how does the handleToolCall function work?"
        "refactor the search logic to improve performance"
    )

    for prompt in "${prompts[@]}"; do
        print_prompt "$prompt"

        echo -e "${GREEN}意图分析结果:${NC}"
        result=$("$HOOK_SCRIPT" --analyze-intent --prompt "$prompt" --format json)
        print_json "$result"

        echo ""
        echo -e "${CYAN}解读:${NC}"

        # 提取关键信息
        explicit=$(echo "$result" | jq -r '.weights.explicit')
        implicit=$(echo "$result" | jq -r '.weights.implicit')
        historical=$(echo "$result" | jq -r '.weights.historical')
        code=$(echo "$result" | jq -r '.weights.code')
        dominant=$(echo "$result" | jq -r '.dominant_dimension')

        echo "  • 显式指令权重 (explicit):   $explicit"
        echo "  • 隐式信号权重 (implicit):   $implicit"
        echo "  • 历史引用权重 (historical): $historical"
        echo "  • 代码符号权重 (code):       $code"
        echo "  • 主导维度: ${BOLD}$dominant${NC}"

        echo ""
        print_separator
        echo ""
    done
}

# 演示 2: 结构化上下文注入
demo_structured_context() {
    print_title "演示 2: 结构化上下文注入 (Structured Context)"

    print_prompt "如何使用 ci_search 工具进行语义搜索？"

    echo -e "${GREEN}注入的结构化上下文:${NC}"
    echo ""

    result=$(echo '{"prompt":"如何使用 ci_search 工具进行语义搜索？"}' | "$HOOK_SCRIPT")

    # 提取各个部分并分别展示
    echo -e "${BOLD}1️⃣ 项目画像 (Project Profile):${NC}"
    echo "$result" | jq -C '.project_profile' 2>/dev/null
    echo ""

    echo -e "${BOLD}2️⃣ 当前状态 (Current State):${NC}"
    echo "$result" | jq -C '.current_state' 2>/dev/null
    echo ""

    echo -e "${BOLD}3️⃣ 任务上下文 (Task Context):${NC}"
    echo "$result" | jq -C '.task_context' 2>/dev/null
    echo ""

    echo -e "${BOLD}4️⃣ 推荐工具 (Recommended Tools):${NC}"
    echo "$result" | jq -C '.recommended_tools' 2>/dev/null
    echo ""

    echo -e "${BOLD}5️⃣ 约束条件 (Constraints):${NC}"
    echo "$result" | jq -C '.constraints' 2>/dev/null
    echo ""
}

# 演示 3: @file 引用功能
demo_file_reference() {
    print_title "演示 3: @file 引用功能 (File Reference)"

    print_prompt "@src/server.ts 这个文件的主要功能是什么？"

    echo -e "${GREEN}📄 自动读取文件内容并注入上下文:${NC}"
    echo ""

    result=$(echo '{"prompt":"@src/server.ts 这个文件的主要功能是什么？"}' | "$HOOK_SCRIPT" --format text)

    echo "$result"
    echo ""
}

# 演示 4: 不同意图类型的对比
demo_intent_comparison() {
    print_title "演示 4: 不同意图类型的工具推荐对比"

    local scenarios=(
        "debug|fix the bug in authentication"
        "modify|add a new export feature"
        "explore|how does the MCP server work?"
    )

    for scenario in "${scenarios[@]}"; do
        IFS='|' read -r intent_type prompt <<< "$scenario"

        print_subtitle "场景: ${intent_type^^}"
        print_prompt "$prompt"

        result=$(echo "{\"prompt\":\"$prompt\"}" | "$HOOK_SCRIPT")

        echo -e "${GREEN}️  推荐工具:${NC}"
        echo "$result" | jq -C '.recommended_tools' 2>/dev/null

        echo ""
        echo -e "${CYAN}说明:${NC}"
        case "$intent_type" in
            debug)
                echo "  Debug 场景推荐: Bug 定位工具 + 调用链追踪"
                ;;
            modify)
                echo "  Modify 场景推荐: 调用链分析 + 影响范围分析"
                ;;
            explore)
                echo "  Explore 场景推荐: 代码搜索 + Graph-RAG 结构理解"
                ;;
        esac

        echo ""
        print_separator
        echo ""
    done
}

# 演示 5: 热点文件分析
demo_hotspot_analysis() {
    print_title "演示 5: 热点文件分析 (Hotspot Analysis)"

    print_subtitle "基于 Git 历史的热点文件检测"

    result=$(echo '{"prompt":"show me the hotspot files"}' | "$HOOK_SCRIPT")

    echo -e "${GREEN}🔥 最近 30 天最活跃的文件:${NC}"
    echo ""

    hotspot_files=$(echo "$result" | jq -r '.current_state.hotspot_files[]' 2>/dev/null)

    if [ -n "$hotspot_files" ]; then
        echo "$hotspot_files" | while IFS= read -r file; do
            echo "  🔥 $file"
        done
    else
        echo "  (无热点文件数据)"
    fi

    echo ""
    echo -e "${CYAN}说明:${NC}"
    echo "  热点文件 = 变更频率高的文件，通常是:"
    echo "  • 核心业务逻辑"
    echo "  • 容易出 Bug 的地方"
    echo "  • 需要重点关注的代码"
    echo ""
}

# 演示 6: 完整的上下文注入流程
demo_full_workflow() {
    print_title "演示 6: 完整的上下文注入流程"

    print_subtitle "模拟真实的用户交互场景"

    local user_prompt="修复 handleToolCall 函数中的错误处理逻辑"

    print_prompt "$user_prompt"

    echo -e "${YELLOW}⚙️  Hook 执行流程:${NC}"
    echo ""
    echo "  1️⃣  接收用户提示"
    echo "  2️⃣  执行 4 维意图分析"
    echo "  3️⃣  提取代码符号 (handleToolCall)"
    echo "  4️⃣  搜索相关代码片段"
    echo "  5️⃣  分析热点文件"
    echo "  6️⃣  推荐相关工具"
    echo "  7️⃣  注入结构化上下文"
    echo ""

    echo -e "${GREEN}最终注入到 Claude 的上下文:${NC}"
    echo ""

    result=$(echo "{\"prompt\":\"$user_prompt\"}" | "$HOOK_SCRIPT")

    # 显示完整的结构化输出
    print_json "$result"

    echo ""
    echo -e "${CYAN}✨ 效果:${NC}"
    echo "  • Claude 自动知道项目使用 TypeScript + Node.js"
    echo "  • Claude 看到了 handleToolCall 函数的定义位置"
    echo "  • Claude 了解了最近修改的热点文件"
    echo "  • Claude 收到了推荐使用的工具 (ci_call_chain, ci_impact)"
    echo "  • Claude 知道了项目的架构约束"
    echo ""
}

# 演示 7: 对比有无上下文注入
demo_comparison() {
    print_title "演示 7: 有无上下文注入的对比"

    print_subtitle "场景: 询问如何修复一个 Bug"

    local prompt="fix the bug in search function"

    echo -e "${RED}没有上下文注入:${NC}"
    echo ""
    echo "  Claude 收到的信息:"
    echo "    • 用户提示: \"$prompt\""
    echo "    • 没有项目信息"
    echo "    • 不知道 search 函数在哪里"
    echo "    • 不知道项目使用什么技术栈"
    echo "    • 不知道相关的热点文件"
    echo ""
    echo "  Claude 的回答可能:"
    echo "    • 询问更多细节"
    echo "    • 给出通用的建议"
    echo "    • 需要多轮对话才能定位问题"
    echo ""

    print_separator
    echo ""

    echo -e "${GREEN}有上下文注入:${NC}"
    echo ""

    result=$(echo "{\"prompt\":\"$prompt\"}" | "$HOOK_SCRIPT")

    echo "  Claude 收到的信息:"
    echo "    • 用户提示: \"$prompt\""

    # 提取关键信息
    tech_stack=$(echo "$result" | jq -r '.project_profile.tech_stack | join(", ")' 2>/dev/null)
    echo "    • 项目技术栈: $tech_stack"

    relevant_file=$(echo "$result" | jq -r '.task_context.relevant_snippets[0].file // "未找到"' 2>/dev/null)
    echo "    • 相关代码: $relevant_file"

    hotspot_count=$(echo "$result" | jq -r '.current_state.hotspot_files | length' 2>/dev/null)
    echo "    • 热点文件: $hotspot_count 个"

    tools=$(echo "$result" | jq -r '.recommended_tools[].tool' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    echo "    • 推荐工具: $tools"

    echo ""
    echo "  Claude 的回答可能:"
    echo "    • 直接定位到 search 函数的位置"
    echo "    • 分析相关的调用链"
    echo "    • 检查热点文件中的相关代码"
    echo "    • 使用推荐的工具进行深入分析"
    echo "    • 一次性给出准确的修复建议"
    echo ""
}

# 主菜单
show_menu() {
    clear
    print_title "DevBooks 上下文注入 Hook 演示"

    echo -e "${BOLD}选择演示场景:${NC}"
    echo ""
    echo "  1. 四维意图分析 (4D Intent Analysis)"
    echo "  2. 结构化上下文注入 (Structured Context)"
    echo "  3. @file 引用功能 (File Reference)"
    echo "  4. 不同意图类型的工具推荐对比"
    echo "  5. 热点文件分析 (Hotspot Analysis)"
    echo "  6. 完整的上下文注入流程"
    echo "  7. 有无上下文注入的对比"
    echo "  8. 运行所有演示"
    echo "  0. 退出"
    echo ""
    echo -n "请选择 (0-8): "
}

# 主循环
main() {
    while true; do
        show_menu
        read -r choice

        case $choice in
            1)
                demo_intent_analysis
                ;;
            2)
                demo_structured_context
                ;;
            3)
                demo_file_reference
                ;;
            4)
                demo_intent_comparison
                ;;
            5)
                demo_hotspot_analysis
                ;;
            6)
                demo_full_workflow
                ;;
            7)
                demo_comparison
                ;;
            8)
                demo_intent_analysis
                demo_structured_context
                demo_file_reference
                demo_intent_comparison
                demo_hotspot_analysis
                demo_full_workflow
                demo_comparison
                ;;
            0)
                echo ""
                echo -e "${GREEN}感谢使用！${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo ""
                echo -e "${RED}无效选择，请重试${NC}"
                sleep 2
                continue
                ;;
        esac

        echo ""
        echo -e "${YELLOW}按 Enter 键返回菜单...${NC}"
        read -r
    done
}

# 检查是否有命令行参数（非交互模式）
if [ $# -gt 0 ]; then
    case "$1" in
        --all)
            demo_intent_analysis
            demo_structured_context
            demo_file_reference
            demo_intent_comparison
            demo_hotspot_analysis
            demo_full_workflow
            demo_comparison
            ;;
        --intent)
            demo_intent_analysis
            ;;
        --structured)
            demo_structured_context
            ;;
        --file-ref)
            demo_file_reference
            ;;
        --comparison)
            demo_intent_comparison
            ;;
        --hotspot)
            demo_hotspot_analysis
            ;;
        --workflow)
            demo_full_workflow
            ;;
        --compare)
            demo_comparison
            ;;
        --help)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --all         运行所有演示"
            echo "  --intent      四维意图分析"
            echo "  --structured  结构化上下文注入"
            echo "  --file-ref    @file 引用功能"
            echo "  --comparison  意图类型对比"
            echo "  --hotspot     热点文件分析"
            echo "  --workflow    完整工作流程"
            echo "  --compare     有无上下文注入对比"
            echo "  --help        显示帮助"
            echo ""
            echo "不带参数运行将进入交互模式"
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
else
    # 交互模式
    main
fi
