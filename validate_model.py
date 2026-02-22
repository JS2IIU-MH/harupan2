"""
YOLOv8 ONNX モデルの検証スクリプト
- モデルの入出力仕様を確認
- テスト画像で推論を実行し、検出結果を確認
"""
import sys
import numpy as np

try:
    import onnxruntime as ort
except ImportError:
    print("ERROR: onnxruntime が必要です。 pip install onnxruntime")
    sys.exit(1)

MODEL_PATH = r"assets\models\best.onnx"
LABELS = ["p05", "p10", "p15", "p20", "p25", "p30"]
SCORES = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
CONF_THRESHOLD = 0.6
INPUT_SIZE = 640


def inspect_model():
    """モデルの入出力仕様を表示"""
    print("=" * 60)
    print("モデル仕様の確認")
    print("=" * 60)

    session = ort.InferenceSession(MODEL_PATH)

    print("\n--- 入力 ---")
    for inp in session.get_inputs():
        print(f"  名前: {inp.name}")
        print(f"  形状: {inp.shape}")
        print(f"  型:   {inp.type}")

    print("\n--- 出力 ---")
    for out in session.get_outputs():
        print(f"  名前: {out.name}")
        print(f"  形状: {out.shape}")
        print(f"  型:   {out.type}")

    return session


def run_inference_with_image(session, image_path):
    """実画像で推論を実行"""
    try:
        from PIL import Image
    except ImportError:
        print("WARNING: Pillow が必要です。 pip install Pillow")
        return

    print(f"\n{'=' * 60}")
    print(f"画像テスト: {image_path}")
    print("=" * 60)

    img = Image.open(image_path).convert("RGB")
    orig_w, orig_h = img.size
    print(f"  元画像サイズ: {orig_w} x {orig_h}")

    # レターボックス前処理
    scale = min(INPUT_SIZE / orig_w, INPUT_SIZE / orig_h)
    new_w = int(orig_w * scale)
    new_h = int(orig_h * scale)
    pad_x = (INPUT_SIZE - new_w) // 2
    pad_y = (INPUT_SIZE - new_h) // 2

    print(f"  スケール: {scale:.4f}, パディング: ({pad_x}, {pad_y})")

    # リサイズ
    img_resized = img.resize((new_w, new_h), Image.BILINEAR)

    # レターボックス画像を作成（灰色パディング 114）
    canvas = np.full((INPUT_SIZE, INPUT_SIZE, 3), 114, dtype=np.uint8)
    canvas[pad_y:pad_y + new_h, pad_x:pad_x + new_w] = np.array(img_resized)

    # CHW 形式、[0, 1] 正規化、バッチ次元追加
    input_data = canvas.astype(np.float32) / 255.0
    input_data = input_data.transpose(2, 0, 1)  # HWC -> CHW
    input_data = np.expand_dims(input_data, axis=0)  # [1, 3, 640, 640]

    print(f"  入力テンソル形状: {input_data.shape}")
    print(f"  入力値範囲: [{input_data.min():.3f}, {input_data.max():.3f}]")

    # 推論
    input_name = session.get_inputs()[0].name
    outputs = session.run(None, {input_name: input_data})

    output = outputs[0]
    print(f"\n  出力テンソル形状: {output.shape}")
    print(f"  出力値範囲: [{output.min():.4f}, {output.max():.4f}]")

    # YOLOv8 出力解析 [1, (4+num_classes), num_boxes]
    if len(output.shape) == 3:
        data = output[0]  # [10, 8400]
        num_features = data.shape[0]
        num_boxes = data.shape[1]
        num_classes = num_features - 4

        print(f"  特徴数: {num_features} (4 bbox + {num_classes} classes)")
        print(f"  ボックス数: {num_boxes}")

        if num_classes != len(LABELS):
            print(f"  WARNING: クラス数不一致! モデル={num_classes}, 期待={len(LABELS)}")

        # 各クラスの最大スコアを表示
        print("\n  --- 各クラスの最大信頼度スコア ---")
        for c in range(num_classes):
            class_scores = data[4 + c]
            max_score = class_scores.max()
            label = LABELS[c] if c < len(LABELS) else f"class_{c}"
            print(f"    {label}: max={max_score:.4f}  (閾値={CONF_THRESHOLD})")

        # 全体の最大スコア
        all_class_scores = data[4:]  # [num_classes, num_boxes]
        max_scores_per_box = all_class_scores.max(axis=0)  # [num_boxes]
        overall_max = max_scores_per_box.max()
        print(f"\n  全体最大スコア: {overall_max:.4f}")

        # 閾値で検出
        print(f"\n  --- 検出結果 (閾値={CONF_THRESHOLD}) ---")
        detections = []
        for i in range(num_boxes):
            max_score = 0
            max_class = 0
            for c in range(num_classes):
                score = data[4 + c, i]
                if score > max_score:
                    max_score = score
                    max_class = c
            if max_score >= CONF_THRESHOLD:
                cx, cy, w, h = data[0, i], data[1, i], data[2, i], data[3, i]
                detections.append((max_class, max_score, cx, cy, w, h))

        if detections:
            print(f"  検出数: {len(detections)}")
            for det in detections[:20]:  # 最大20個表示
                cls, conf, cx, cy, w, h = det
                label = LABELS[cls] if cls < len(LABELS) else f"class_{cls}"
                print(f"    {label}: conf={conf:.4f}, cx={cx:.1f}, cy={cy:.1f}, w={w:.1f}, h={h:.1f}")
        else:
            print("  検出なし")

        # 閾値を下げて再チェック
        for threshold in [0.3, 0.1, 0.01]:
            count = np.sum(max_scores_per_box >= threshold)
            print(f"  閾値 {threshold}: {count} 件検出")

    else:
        print(f"  想定外の出力形状: {output.shape}")


def run_dummy_inference(session):
    """ダミー入力で推論が正常に動作するか確認"""
    print(f"\n{'=' * 60}")
    print("ダミー入力テスト（灰色画像 114/255）")
    print("=" * 60)

    dummy = np.full((1, 3, INPUT_SIZE, INPUT_SIZE), 114.0 / 255.0, dtype=np.float32)
    input_name = session.get_inputs()[0].name
    outputs = session.run(None, {input_name: dummy})
    output = outputs[0]

    print(f"  出力形状: {output.shape}")
    print(f"  出力値範囲: [{output.min():.4f}, {output.max():.4f}]")

    if len(output.shape) == 3:
        data = output[0]
        all_class_scores = data[4:]
        max_scores = all_class_scores.max(axis=0)
        print(f"  最大信頼度: {max_scores.max():.4f}")
        print(f"  閾値超え数 (0.6): {np.sum(max_scores >= 0.6)}")
        print(f"  閾値超え数 (0.1): {np.sum(max_scores >= 0.1)}")


if __name__ == "__main__":
    session = inspect_model()
    run_dummy_inference(session)

    # テスト画像があれば推論
    import os
    test_images = []
    # カレントディレクトリの画像ファイルを検索
    for ext in ["*.jpg", "*.jpeg", "*.png", "*.bmp"]:
        import glob
        test_images.extend(glob.glob(ext))
        test_images.extend(glob.glob(os.path.join("test_images", ext)))

    if test_images:
        for img_path in test_images[:5]:
            run_inference_with_image(session, img_path)
    else:
        print("\n\nテスト画像が見つかりません。")
        print("このスクリプトと同じディレクトリ、または test_images/ フォルダに")
        print("テスト画像を配置して再実行してください。")
