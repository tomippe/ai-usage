# -*- coding: utf-8 -*-
"""Localizer の文言から Resources/Strings*.resx を生成（一回限り・再実行可）。"""
from __future__ import annotations

import xml.etree.ElementTree as ET
from pathlib import Path

WIN = Path(__file__).resolve().parent.parent
RES = WIN / "Resources"

# [key] -> [en, ja, zh-Hans]
STRINGS: dict[str, list[str]] = {
    "noProviders": [
        "No supported AI providers",
        "対応するAIプロバイダが見つかりません",
        "未检测到受支持的 AI 提供商",
    ],
    "loading": ["Loading…", "取得中…", "正在读取…"],
    "unavailable": ["Usage unavailable", "使用率を取得できません", "无法获取使用量"],
    "notLoggedIn": ["Not signed in", "未ログイン", "未登录"],
    "refresh": ["Refresh Now", "今すぐ更新", "立即刷新"],
    "currency": ["Amount Currency", "金額レート", "金额货币"],
    "voiceAlerts": ["Voice Alerts", "音声通知", "语音提醒"],
    "voiceEnabled": ["Enable Voice Alerts", "音声通知を有効にする", "启用语音提醒"],
    "openAtLogin": ["Open at Login", "ログイン時に開く", "登录时打开"],
    "about": ["About AI Usage…", "AI Usage について…", "关于 AI Usage…"],
    "feedback": ["Send Feedback…", "フィードバックを送る…", "发送反馈…"],
    "updates": ["Check for Updates…", "アップデートを確認…", "检查更新…"],
    "restart": ["Restart AI Usage", "AI Usage を再起動", "重新启动 AI Usage"],
    "quit": ["Quit AI Usage", "AI Usage を終了", "退出 AI Usage"],
    "threshold": ["{0}% remaining", "残り{0}%", "剩余 {0}%"],
    "aboutBody": [
        "AI plan usage in a floating window.\nVersion {0}",
        "AIプランの使用率を小窓に表示します。\nバージョン {0}",
        "在悬浮窗口中显示 AI 套餐使用量。\n版本 {0}",
    ],
    "tooltip": [
        "Drag anywhere to move · Right-click for options",
        "どこでもドラッグして移動 · 右クリックでメニュー",
        "拖动窗口任意位置移动 · 右键打开菜单",
    ],
    "speech": ["{0}, {1}, {2} percent remaining.", "{0}、{1}の残り{2}%です", "{0}，{1}剩余 {2}%"],
    "speechStandard": ["usage", "利用枠", "使用额度"],
    "speechCursorNative": ["native quota", "純正枠", "原生额度"],
    "speechCursorApi": ["API quota", "API枠", "API额度"],
    "speechFiveHour": ["5 hour window", "5時間枠", "5小时额度"],
    "speechWeekly": ["weekly window", "週間枠", "每周额度"],
    "cursorSpeech": ["Cursor", "カーソル", "Cursor"],
    "codexSpeech": ["Chat G P T", "チャットGPT", "ChatGPT"],
    "claudeSpeech": ["Claude Code", "クロードコード", "Claude Code"],
    "usd": ["US Dollar", "ドル", "美元"],
    "eur": ["Euro", "ユーロ", "欧元"],
    "jpy": ["Japanese Yen", "円", "日元"],
    "gbp": ["British Pound", "英ポンド", "英镑"],
    "cny": ["Chinese Yuan", "元", "元"],
    "claudeFiveHour": ["5h", "5時間", "5小时"],
    "weekly": ["Weekly", "週間", "每周"],
    "auto": ["Auto", "自動", "自动"],
    "api": ["API", "API", "API"],
    "resetCredits": ["{0} reset credits", "{0}回リセット可能", "可重置 {0} 次"],
    "dash.reset_header": ["Resets at %@.", "リセット日時: {0}", "重置时间：{0}"],
    "dash.duration.24h": ["24h", "24時間", "24小时"],
    "dash.duration.7d": ["7d", "7日", "7天"],
    "dash.duration.30d": ["30d", "30日", "30天"],
    "dash.duration.cycle": ["Cycle", "請求期間", "账单周期"],
    "dash.card.total": ["Total", "合計", "合计"],
    "dash.card.auto": ["Auto", "自動", "自动"],
    "dash.card.api": ["API", "API", "API"],
    "dash.card.ondemand": ["On-Demand", "従量", "按量"],
    "dash.col.model": ["Model", "モデル", "模型"],
    "dash.col.requests": ["Req", "回数", "次数"],
    "dash.col.tokens": ["Tokens", "トークン", "令牌"],
    "dash.col.spend": ["Spend", "金額", "金额"],
    "dash.chart.empty": [
        "No usage in this range",
        "この期間の使用量はありません",
        "此期间无用量",
    ],
    "dash.table.empty": [
        "No rows in this range",
        "この期間にデータがありません",
        "此期间无数据",
    ],
}

RESX_HEADER = """<?xml version="1.0" encoding="utf-8"?>
<root>
  <xsd:schema id="root" xmlns="" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:msdata="urn:schemas-microsoft-com:xml-msdata">
    <xsd:import namespace="http://www.w3.org/XML/1998/namespace" />
    <xsd:element name="root" msdata:IsDataSet="true">
      <xsd:complexType>
        <xsd:choice maxOccurs="unbounded">
          <xsd:element name="metadata">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" />
              </xsd:sequence>
              <xsd:attribute name="name" use="required" type="xsd:string" />
              <xsd:attribute name="type" type="xsd:string" />
              <xsd:attribute name="mimetype" type="xsd:string" />
              <xsd:attribute ref="xml:space" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="assembly">
            <xsd:complexType>
              <xsd:attribute name="alias" type="xsd:string" />
              <xsd:attribute name="name" type="xsd:string" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="data">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />
                <xsd:element name="comment" type="xsd:string" minOccurs="0" msdata:Ordinal="2" />
              </xsd:sequence>
              <xsd:attribute name="name" type="xsd:string" use="required" />
              <xsd:attribute name="type" type="xsd:string" />
              <xsd:attribute name="mimetype" type="xsd:string" />
              <xsd:attribute ref="xml:space" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="resheader">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />
              </xsd:sequence>
              <xsd:attribute name="name" type="xsd:string" use="required" />
            </xsd:complexType>
          </xsd:element>
        </xsd:choice>
      </xsd:complexType>
    </xsd:element>
  </xsd:schema>
  <resheader name="resmimetype">
    <value>text/microsoft-resx</value>
  </resheader>
  <resheader name="version">
    <value>2.0</value>
  </resheader>
  <resheader name="reader">
    <value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
  <resheader name="writer">
    <value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
"""


def write_resx(path: Path, lang_index: int) -> None:
    parts = [RESX_HEADER]
    for key, vals in STRINGS.items():
        val = vals[lang_index]
        esc = (
            val.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\r\n", "&#10;")
            .replace("\n", "&#10;")
        )
        parts.append(f'  <data name="{key}" xml:space="preserve">\n    <value>{esc}</value>\n  </data>\n')
    parts.append("</root>\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(parts), encoding="utf-8")


def main() -> None:
    write_resx(RES / "Strings.resx", 0)
    write_resx(RES / "Strings.ja.resx", 1)
    write_resx(RES / "Strings.zh-Hans.resx", 2)
    print(f"Wrote {RES / 'Strings.resx'}")
    print(f"Wrote {RES / 'Strings.ja.resx'}")
    print(f"Wrote {RES / 'Strings.zh-Hans.resx'}")


if __name__ == "__main__":
    main()
