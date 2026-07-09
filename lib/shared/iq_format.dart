import 'dart:math' as math;

/// Intellectパーセンタイル（`profiles.intellect_percentile`。値が小さいほど上位、
/// 例: 上位5% → `5`）を、平均100・標準偏差15の標準的なIQスケールに変換する。
///
/// バックエンドにIQ値そのものを保持するカラムは無いため（`intellect_score`/
/// `intellect_percentile`のみ、design/system.md 1章）、標準正規分布の逆累積分布関数を用いて
/// クライアント側でパーセンタイルからIQスケールへ変換する。
/// 例: 上位50%（中央値）→ IQ100、上位2.3%相当 → IQ約130。
int? intellectIqScore(num? percentile) {
  if (percentile == null) return null;
  // 上位p% → 母集団の (100 - p)% よりスコアが高い、という累積確率に変換する。
  final clamped = percentile.clamp(0.1, 99.9);
  final cumulativeProbability = 1 - (clamped / 100);
  final z = _inverseNormalCdf(cumulativeProbability);
  return (100 + 15 * z).round();
}

/// 標準正規分布の逆累積分布関数（分位点関数）の近似計算。
/// Acklamのアルゴリズムによる有理近似（相対誤差 1.15e-9 以下）。
double _inverseNormalCdf(double p) {
  const a = [
    -3.969683028665376e+01,
    2.209460984245205e+02,
    -2.759285104469687e+02,
    1.383577518672690e+02,
    -3.066479806614716e+01,
    2.506628277459239e+00,
  ];
  const b = [
    -5.447609879822406e+01,
    1.615858368580409e+02,
    -1.556989798598866e+02,
    6.680131188771972e+01,
    -1.328068155288572e+01,
  ];
  const c = [
    -7.784894002430293e-03,
    -3.223964580411365e-01,
    -2.400758277161838e+00,
    -2.549732539343734e+00,
    4.374664141464968e+00,
    2.938163982698783e+00,
  ];
  const d = [
    7.784695709041462e-03,
    3.224671290700398e-01,
    2.445134137142996e+00,
    3.754408661907416e+00,
  ];

  const pLow = 0.02425;
  final pHigh = 1 - pLow;

  if (p < pLow) {
    final q = math.sqrt(-2 * math.log(p));
    return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }
  if (p <= pHigh) {
    final q = p - 0.5;
    final r = q * q;
    return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) *
        q /
        (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
  }
  final q = math.sqrt(-2 * math.log(1 - p));
  return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
      ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
}
