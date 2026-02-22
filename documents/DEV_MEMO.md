# 開発メモ (DEV_MEMO)

本ドキュメントは、はるぱん2 の開発時に参照する技術的なメモです。

---

## プロジェクト構成

```
lib/
├── main.dart                    # エントリポイント・MaterialApp 設定
├── constants/
│   └── app_constants.dart       # 色・閾値・ラベル等の定数
├── models/
│   └── detection_result.dart    # 検出結果データクラス
├── providers/
│   └── app_providers.dart       # Riverpod プロバイダ定義
├── services/
│   ├── image_utils.dart         # カメラ画像の前処理（YUV→RGB・リサイズ）
│   └── yolo_service.dart        # ONNX 推論・後処理（NMS）
├── screens/
│   └── camera_screen.dart       # メイン画面（カメラ＋検出ループ）
└── widgets/
    ├── bounding_box_overlay.dart # バウンディングボックス描画
    ├── control_buttons.dart      # カメラ切替・シェアボタン
    └── score_overlay.dart        # 合計点オーバーレイ
```

## セットアップ

```bash
flutter pub get
flutter run
```

### リリースビルド

```bash
# Android (App Bundle)
flutter build appbundle --release

# iOS
flutter build ios --release
```

---

## 技術選定

### 状態管理: Riverpod を選択した理由

| 手法 | 判断 | 理由 |
|------|------|------|
| **Riverpod** | **採用** | コンパイル時型安全・非同期状態（カメラストリーム・推論結果）の管理が容易・`ref.watch` によるリアクティブ UI 更新・テスト容易性・少ないボイラープレート |
| Provider | 不採用 | Riverpod の前身。`BuildContext` 依存でテストしにくく、型安全性が低い。Riverpod への移行が公式推奨 |
| Bloc | 不採用 | イベント/ステートクラスの定義が多く、単一画面アプリにはボイラープレート過剰 |
| setState | 不採用 | カメラ＋推論＋スコア計算を 1 つの Widget で管理すると保守性が低下 |

### 技術スタック

| 区分 | 技術 |
|------|------|
| フレームワーク | Flutter |
| 物体検出モデル | YOLOv8（ONNX） |
| 推論エンジン | onnxruntime_flutter（オンデバイス推論） |
| 状態管理 | Riverpod |

---

## 推論パラメータ

| パラメータ | 値 | 説明 |
|---|---|---|
| モデル入力サイズ | 640×640 | YOLOv8 標準 |
| 信頼度スコア閾値 | 0.38 | この値未満の検出は除外（チューニング済み） |
| NMS IoU 閾値 | 0.45 | 下記参照 |

これらは `lib/constants/app_constants.dart` で定数化されており、容易に調整可能です。

### NMS（Non-Maximum Suppression）と IoU 閾値

物体検出モデルは同じ物体に対して複数のバウンディングボックスを出力することがあります。NMS はこれらの重複を除去する後処理アルゴリズムです。

- **IoU（Intersection over Union）**: 2 つのボックスの重なり度合いを 0〜1 で表す指標
  - `IoU = (重なり面積) / (2 つのボックスの合計面積 − 重なり面積)`
- **IoU 閾値 = 0.45** の意味: 重なりが 45% 以上なら「同じ物体の検出」と判断し、信頼度が低い方を除去
  - 値を **小さく** → 少しの重なりでも除去 → 重複は減るが、近接シールを見逃すリスク
  - 値を **大きく** → 重なりが大きくないと除去しない → 近接シールは拾えるが、同一シールの重複が増える
  - **0.45** は物体検出の標準的な値

### 認識対象シールとクラス定義

YOLOv8 のクラスインデックス順（`train/weights/best.onnx` メタデータ準拠）:

| インデックス | ラベル | 点数 |
|:---:|--------|:---:|
| 0 | p05 | 0.5 点 |
| 1 | p10 | 1.0 点 |
| 2 | p15 | 1.5 点 |
| 3 | p25 | 2.5 点 |
| 4 | p30 | 3.0 点 |
| 5 | p20 | 2.0 点 |

> **注意**: インデックス順が点数順ではない（p25, p30 が p20 より先）。モデルの学習時のクラス順に依存しているため、変更不可。

---

## デザイン定数

| 項目 | 値 |
|------|------|
| メインカラー | `#134A96` |
| アクセントカラー | `#E4004F` |

---

## モデル学習履歴

学習済みモデルの各バージョンは以下のディレクトリに保存されています:

- `train/` — 最新モデル（リリース使用）
- `train_ver1/` — バージョン 1
- `train_ver2/` — バージョン 2
- `train_ver3/` — バージョン 3

各ディレクトリには `args.yaml`（学習パラメータ）、`results.csv`（学習結果）、`weights/`（モデルファイル）が含まれます。
