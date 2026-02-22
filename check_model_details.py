"""
ONNX モデルのクラススコアが sigmoid 済みかどうかを検証し、
モデル精度の問題を詳細に分析する。
"""
import numpy as np
import onnxruntime as ort

MODEL_PATH = r"assets\models\best.onnx"
INPUT_SIZE = 640
LABELS = ["p05", "p10", "p15", "p20", "p25", "p30"]


def check_sigmoid():
    session = ort.InferenceSession(MODEL_PATH)
    input_name = session.get_inputs()[0].name

    # ランダム画像で推論（物体っぽいものが映る可能性あり）
    np.random.seed(42)
    random_input = np.random.rand(1, 3, INPUT_SIZE, INPUT_SIZE).astype(np.float32)
    outputs = session.run(None, {input_name: random_input})
    data = outputs[0][0]  # [10, 8400]

    class_scores = data[4:]  # [6, 8400]

    print("=" * 60)
    print("クラススコアの分析（sigmoid 判定）")
    print("=" * 60)

    print(f"\n  クラススコア全体:")
    print(f"    最小値: {class_scores.min():.6f}")
    print(f"    最大値: {class_scores.max():.6f}")
    print(f"    平均値: {class_scores.mean():.6f}")
    print(f"    標準偏差: {class_scores.std():.6f}")

    # sigmoid 済みなら全て [0, 1] の範囲
    all_in_01 = np.all((class_scores >= 0) & (class_scores <= 1))
    has_negative = np.any(class_scores < 0)
    has_above_1 = np.any(class_scores > 1)

    print(f"\n  [0, 1] 範囲内: {all_in_01}")
    print(f"  負の値あり: {has_negative}")
    print(f"  1 超えの値あり: {has_above_1}")

    if all_in_01:
        print("\n  → クラススコアは sigmoid 済みと判断")
    elif has_negative or has_above_1:
        print("\n  → クラススコアは RAW LOGIT（sigmoid 未適用）!!")
        print("  → Flutter 側で sigmoid を適用する必要があります")

        # sigmoid を適用した場合のスコア
        sigmoided = 1.0 / (1.0 + np.exp(-class_scores))
        print(f"\n  sigmoid 適用後:")
        print(f"    最小値: {sigmoided.min():.6f}")
        print(f"    最大値: {sigmoided.max():.6f}")
        print(f"    平均値: {sigmoided.mean():.6f}")

    # バウンディングボックス座標の分析
    bbox = data[:4]  # [4, 8400]
    print(f"\n  バウンディングボックス座標:")
    print(f"    cx 範囲: [{bbox[0].min():.1f}, {bbox[0].max():.1f}]")
    print(f"    cy 範囲: [{bbox[1].min():.1f}, {bbox[1].max():.1f}]")
    print(f"    w  範囲: [{bbox[2].min():.1f}, {bbox[2].max():.1f}]")
    print(f"    h  範囲: [{bbox[3].min():.1f}, {bbox[3].max():.1f}]")


def check_onnx_graph():
    """ONNX グラフの最終ノードを確認して sigmoid の有無を判定"""
    try:
        import onnx
        model = onnx.load(MODEL_PATH)
        graph = model.graph

        print(f"\n{'=' * 60}")
        print("ONNX グラフ分析")
        print("=" * 60)

        # 出力ノードを探す
        output_names = [o.name for o in graph.output]
        print(f"  出力名: {output_names}")

        # 最後の数ノードを表示
        print(f"\n  最後の5つのノード:")
        for node in graph.node[-5:]:
            print(f"    {node.op_type}: {list(node.input)} -> {list(node.output)}")

        # Sigmoid ノードがあるか
        sigmoid_nodes = [n for n in graph.node if n.op_type == "Sigmoid"]
        print(f"\n  Sigmoid ノード数: {len(sigmoid_nodes)}")

    except ImportError:
        print("\nonnx パッケージがインストールされていないため、グラフ分析をスキップ")


def test_with_pt():
    """PyTorch モデル(best.pt)があれば ultralytics で直接テスト"""
    try:
        from ultralytics import YOLO

        pt_path = r"train\weights\best.pt"
        print(f"\n{'=' * 60}")
        print(f"ultralytics による直接推論テスト: {pt_path}")
        print("=" * 60)

        model = YOLO(pt_path)
        print(f"  モデル情報: {model.info(verbose=False)}")

        # ダミー画像で推論
        dummy = np.full((640, 640, 3), 114, dtype=np.uint8)
        results = model.predict(dummy, conf=0.01, verbose=False)

        print(f"  ダミー画像での検出数: {len(results[0].boxes)}")
        if len(results[0].boxes) > 0:
            for box in results[0].boxes[:5]:
                cls = int(box.cls[0])
                conf = float(box.conf[0])
                label = LABELS[cls] if cls < len(LABELS) else f"c{cls}"
                print(f"    {label}: conf={conf:.4f}")

    except ImportError:
        print("\nultralytics がインストールされていないため、PT テストをスキップ")
    except Exception as e:
        print(f"\nPT テスト中にエラー: {e}")


if __name__ == "__main__":
    check_sigmoid()
    check_onnx_graph()
    test_with_pt()
