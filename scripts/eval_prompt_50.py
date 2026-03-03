#!/usr/bin/env python3
import argparse
import concurrent.futures
import json
import os
import re
import time
from dataclasses import dataclass
from typing import List, Dict, Tuple

import requests

BASELINE_PROMPT = """任务：把用户输入改写为更清晰、可执行的文本。

强约束：
1. 只允许重写、纠错、重排。禁止新增用户未提及的信息。
2. 禁止添加角色设定、身份描述、背景故事、解释性前后缀。
3. 禁止脑补功能、步骤、验收标准、风险项；除非原文已明确提到。
4. 保留原始意图、约束、数字、专有名词。
5. 修正常见错别字和不规范术语，不改变业务含义。
6. 仅输出最终改写结果，不输出任何说明。
7. 不使用星号、井号、反引号、方括号等特殊结构化符号。
8. 不得扩写成新的需求清单、功能拆解或实施方案；除非原文已经给出这些结构。
9. 输出长度默认不超过原文约 1.25 倍；若原文很短，只做必要纠错与术语规范。
10. 若原文已清晰，优先最小改动；可直接返回轻微纠错后的原句。

结构规则：
1. 如果原文是列表/分点，保持分点并优化语序。
2. 如果原文是自然句子，输出为简洁段落，不强行套模板。

场景补充：
1. 偏向 Web Coding 语境做术语校正，例如 prompt、onboarding、frontend、backend、API。
2. 不新增任何未给出的技术方案。
3. 不自动补充“角色设定”“验收标准”“风险评估”“里程碑”等模板化段落。"""

OPTIMIZED_PROMPT = """只改写用户输入，不做扩写。
只允许纠错、语序优化、术语规范。
禁止新增原文未提及的信息、步骤、方案、角色、验收、风险、里程碑。
保留原始意图、约束、数字、专有名词。
原文是分点就保持分点；原文是自然句就保持自然句。
原文已清晰时仅做最小改动。
不得反问用户，不得要求用户补充文本。
不输出解释、标题、前后缀。
禁止输出：改写后、优化后、根据你的、作为、我将、下面是。
禁止输出符号：* # ` [ ]。
Web Coding 术语仅在必要时纠正为 prompt、onboarding、frontend、backend、API。
仅输出最终改写文本。"""

CASES = [
    "把首页改一下，左边菜单右边内容，别整那么多弹窗。",
    "onbording第一步要先授权辅助功能 第二步选风格 第三步设热键",
    "请把rewrite速度调快一点但是别乱改我原话",
    "快捷键设置点了没反应，支持用户直接按键盘录入，不要下拉选择",
    "我按住说话松开后没有进入thinking，还是输入中",
    "把这个 toast 做短一点，错误要能手动关闭，还要自动消失",
    "输入框太长了，最多十个中文宽度，超出就滚动",
    "不要把小红书拉起来，热键只触发语音输入",
    "授权状态老是脏数据，重编译后要清理再重新申请",
    "请你把模型切到 gemini-2.5-flash-lite",
    "历史记录最多保留100条，要能看原文和改写并复制",
    "没有焦点时别丢消息，提示用户复制后手动粘贴",
    "thinking阶段只要AI图标，不要显示思考中三个字",
    "错误提示现在太宽了，限制最大宽度，图标文字对齐",
    "准备中这个状态条宽度要跟文字自适应，不要占满整行",
    "把输入中的图标改成声波动画，不要转圈loading",
    "我希望初始状态输入框里显示‘请开始说话’文字提示",
    "有文本后就替换为实时文本，单行显示，不换行",
    "onboarding和主界面窗口尺寸要统一",
    "onboarding要做成每步单屏，不要把信息堆在一个页面",
    "辅助功能授权要单独一步，而且写清楚重启要求",
    "权限异常文案要更短更清楚，别吓人",
    "启动后请直接可用，不要每次都让我重新配权限",
    "现在改写会自己加角色身份，这个要禁止",
    "不要输出星号井号这些格式符号",
    "如果原文已经清楚就别大改，最多修错别字",
    "把web coding里常用词纠正下，比如front end改frontend",
    "把后端接口地址写法统一成API endpoint",
    "请把这句话润色下：你说你是谁我操现在都想好了",
    "我说的是做一个输入条，不是做一个大面板",
    "停止输入后应立即进入改写，进度条先快后慢到99",
    "完成后瞬间100并发送，不要停在结果展示",
    "发送成功不需要显示改写结果，直接消失",
    "如果改写失败，回退本地文本并给可关闭错误提示",
    "把快捷键冲突校验做上，默认拒绝高冲突组合",
    "支持单键和双键组合，不要限制用户",
    "设置页里不要再放输入记录入口，历史记录已有",
    "登录后页面采用左侧菜单+右侧面板布局",
    "首页、实时输入、历史记录、设置都要可点可用",
    "图标简化，只保留线条动画，去掉旁边文字",
    "状态反馈改成‘⚙️ 优化中’",
    "别用语音播报开始说话，文字提示就够了",
    "输入中声音滴一下后仍显示输入中，这是状态机bug",
    "修复崩溃：主线程按钮点击触发EXC_BAD_ACCESS",
    "把安装版签名固定，不要每次身份变导致权限失效",
    "Xcode里打开后先跑build再跑相关测试",
    "这个需求保持原句，别扩写：支持修改快捷键",
    "把输入框位置放在屏幕中下，不要右上角",
    "全屏场景下也要显示输入条，避免被窗口遮挡",
    "如果用户取消输入，给轻提示后自动收起",
]


@dataclass
class EvalItem:
    idx: int
    text: str
    baseline_raw: str
    baseline_final: str
    optimized_raw: str
    optimized_final: str
    baseline_issues: List[str]
    optimized_issues: List[str]
    baseline_ratio: float
    optimized_ratio: float


def defaults_read(key: str) -> str:
    return os.popen(f"defaults read com.voiceinput.shared {key} 2>/dev/null").read().strip().strip('"')


def call_model(endpoint: str, api_key: str, model: str, system_prompt: str, text: str, timeout: int) -> str:
    payload = {
        "model": model,
        "messages": [{"role": "system", "content": system_prompt}, {"role": "user", "content": text}],
        "temperature": 0.1,
        "max_tokens": 512,
    }
    for _ in range(2):
        try:
            resp = requests.post(endpoint, headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}, json=payload, timeout=timeout)
            if resp.status_code < 300:
                content = (resp.json().get("choices", [{}])[0].get("message", {}).get("content") or "").strip()
                if content:
                    return content
            time.sleep(0.15)
        except Exception:
            time.sleep(0.15)
    return ""


def extract_semantic_tokens(text: str) -> List[str]:
    tokens: List[str] = []
    for pattern in (r"[A-Za-z][A-Za-z0-9_\-\.]{1,}", r"[\u4e00-\u9fff]{2,}"):
        tokens.extend(re.findall(pattern, text))
    uniq = []
    seen = set()
    for t in tokens:
        k = t.lower()
        if k not in seen:
            seen.add(k)
            uniq.append(t)
    return uniq[:20]


def is_prompt_leak(text: str) -> bool:
    hit_terms = [
        "强约束", "结构规则", "场景补充", "仅允许重写", "不得扩写", "不自动补充",
        "任务：把用户输入改写", "system prompt", "你是文本改写器", "只输出改写后的正文"
    ]
    hit = sum(1 for t in hit_terms if t.lower() in text.lower())
    if hit >= 2:
        return True
    return ("1." in text and "2." in text and "3." in text and "强约束" in text)


def has_forbidden_formatting(text: str) -> bool:
    prefixes = [
        "改写后", "优化后", "根据你的", "作为", "我将", "下面是",
        "请提供需要改写", "请提供要改写", "请提供需要优化", "请提供文本"
    ]
    if any(text.startswith(p) for p in prefixes):
        return True
    return any(sym in text for sym in ["*", "#", "`", "[", "]"])


def is_length_too_long(original: str, output: str) -> bool:
    if not original:
        return False
    ratio = len(output) / len(original)
    if len(original) <= 12:
        return ratio > 1.8
    return ratio > 1.35


def is_semantic_drift(original: str, output: str) -> bool:
    source_tokens = set(t.lower() for t in extract_semantic_tokens(original))
    if len(source_tokens) < 2:
        return False
    out = output.lower()
    overlap = sum(1 for t in source_tokens if t in out)
    return (overlap / len(source_tokens)) < 0.22


def sanitize_like_app(output: str, original: str) -> Tuple[str, bool]:
    out = output.strip()
    if out.startswith("```"):
        out = out.replace("```", "").strip()

    reject = (
        not out
        or is_prompt_leak(out)
        or has_forbidden_formatting(out)
        or is_length_too_long(original, out)
        or is_semantic_drift(original, out)
    )
    if reject:
        return original, True
    return out, False


def analyze(inp: str, out: str, was_fallback: bool) -> Tuple[List[str], float]:
    issues: List[str] = []
    ratio = (len(out) / len(inp)) if inp else 1.0
    if was_fallback:
        issues.append("触发防跑偏回退")
    if out == inp:
        issues.append("最小改写/原样返回")
    return issues, round(ratio, 2)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run 50-case prompt A/B evaluation")
    parser.add_argument("--out-prefix", default="docs/eval/prompt_ab_eval_50_rerun", help="Output file prefix")
    parser.add_argument("--timeout", type=int, default=10, help="HTTP timeout seconds")
    parser.add_argument("--workers", type=int, default=10, help="Parallel workers")
    args = parser.parse_args()

    api_key = defaults_read("llmAPIKey")
    base_url = defaults_read("llmAPIBaseURL") or "https://oneapi.gemiaude.com/v1"
    model = defaults_read("llmModel") or "gemini-2.5-flash-lite"
    endpoint = base_url.rstrip("/") + "/chat/completions"

    if not api_key:
        raise SystemExit("Missing API key in defaults: com.voiceinput.shared llmAPIKey")

    def run_case(pair: Tuple[int, str]) -> EvalItem:
        idx, text = pair
        b_raw = call_model(endpoint, api_key, model, BASELINE_PROMPT, text, args.timeout)
        o_raw = call_model(endpoint, api_key, model, OPTIMIZED_PROMPT, text, args.timeout)
        b_final, b_fallback = sanitize_like_app(b_raw, text)
        o_final, o_fallback = sanitize_like_app(o_raw, text)
        b_issues, b_ratio = analyze(text, b_final, b_fallback)
        o_issues, o_ratio = analyze(text, o_final, o_fallback)
        return EvalItem(idx, text, b_raw, b_final, o_raw, o_final, b_issues, o_issues, b_ratio, o_ratio)

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.workers)) as ex:
        items = list(ex.map(run_case, list(enumerate(CASES, start=1))))
    items.sort(key=lambda x: x.idx)

    os.makedirs(os.path.dirname(args.out_prefix), exist_ok=True)
    json_path = args.out_prefix + ".json"
    md_path = args.out_prefix + ".md"

    payload: List[Dict[str, object]] = []
    for it in items:
        payload.append(
            {
                "id": it.idx,
                "input": it.text,
                "baseline_raw": it.baseline_raw,
                "baseline_final": it.baseline_final,
                "optimized_raw": it.optimized_raw,
                "optimized_final": it.optimized_final,
                "baseline_issues": it.baseline_issues,
                "optimized_issues": it.optimized_issues,
                "baseline_ratio": it.baseline_ratio,
                "optimized_ratio": it.optimized_ratio,
            }
        )

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    b_fallback = sum(1 for it in items if "触发防跑偏回退" in it.baseline_issues)
    o_fallback = sum(1 for it in items if "触发防跑偏回退" in it.optimized_issues)

    lines = [
        "# Prompt A/B Eval (Rerun, App-like Guardrails)",
        "",
        f"- Model: `{model}`",
        f"- Endpoint: `{endpoint}`",
        f"- Baseline回退次数: **{b_fallback}/50**",
        f"- Optimized回退次数: **{o_fallback}/50**",
        "",
    ]

    for it in items:
        lines.append(f"## {it.idx}")
        lines.append(f"原始输入：{it.text}")
        lines.append(f"Baseline原始输出：{it.baseline_raw or '(空)'}")
        lines.append(f"Baseline最终输出：{it.baseline_final}")
        lines.append(f"Baseline分析：长度比 {it.baseline_ratio}；标记：{'；'.join(it.baseline_issues) if it.baseline_issues else '无'}")
        lines.append(f"Optimized原始输出：{it.optimized_raw or '(空)'}")
        lines.append(f"Optimized最终输出：{it.optimized_final}")
        lines.append(f"Optimized分析：长度比 {it.optimized_ratio}；标记：{'；'.join(it.optimized_issues) if it.optimized_issues else '无'}")
        lines.append("")

    with open(md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(json_path)
    print(md_path)
    print(f"baseline_fallback={b_fallback} optimized_fallback={o_fallback}")


if __name__ == "__main__":
    main()
