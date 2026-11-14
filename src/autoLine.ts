/* 自动选线已停用：唯一播放源固定为 huangguoai.com。
 *
 * 保留本模块的导出只是为了兼容原有入口与设置页调用；这里不再读取发布页、
 * 不再探测镜像、不再调用 line_auto / line_mirrors / line_health，也不会切源。
 */
import { logLine } from "./api";

/** 唯一固定主源。 */
const MAIN_BASE = "https://huangguoai.com";

/** 自动选线永远关闭；设置页据此显示为关闭状态。 */
export const autoLineEnabled = (): boolean => false;

/** 兼容旧设置页的开关回调：记录一次请求即可，不产生任何网络请求。 */
export const setAutoLine = (on: boolean): void => {
  logLine(`[line] auto select disabled, requested=${on ? "on" : "off"} fixed=${MAIN_BASE}`);
};

/** 最近一次选择结果，仅供展示 / 排查。 */
export let lastPick: { base: string; tier: string; ms: number } | null = {
  base: MAIN_BASE,
  tier: "main",
  ms: 0,
};

/** 兼容旧调用：始终停留在主源，不请求、不切换。 */
export async function pickLine(reason: string, _force = false): Promise<void> {
  lastPick = { base: MAIN_BASE, tier: "main", ms: 0 };
  logLine(`[line] fixed(${reason}) ${MAIN_BASE}`);
}

/** 启动时不再挂自动选线事件或巡检。 */
export function initAutoLine(): void {
  lastPick = { base: MAIN_BASE, tier: "main", ms: 0 };
  logLine(`[line] fixed source ${MAIN_BASE}`);
}
