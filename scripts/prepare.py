"""Minimal preprocessor: load → clean → profile → write parquet + profile.json."""

import argparse
import json
from pathlib import Path

import pandas as pd

ID_LIKE = ("id", "uuid", "customerid")


def load(path: Path) -> pd.DataFrame:
    if path.suffix.lower() in {".xlsx", ".xls"}:
        return pd.read_excel(path)
    if path.suffix.lower() == ".parquet":
        return pd.read_parquet(path)
    return pd.read_csv(path)


def infer_target_type(y: pd.Series) -> str:
    n = y.nunique(dropna=True)
    if n == 2:
        return "binary_classification"
    if y.dtype.kind in "OSU" or (y.dtype.kind in "iu" and n <= 20):
        return "multiclass_classification"
    return "regression"


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    p.add_argument("--target", default=None, help="Target column name; defaults to last column.")
    args = p.parse_args()

    df = load(args.input)

    # Drop obvious identifier columns.
    df = df.drop(columns=[c for c in df.columns if c.lower() in ID_LIKE], errors="ignore")

    # Coerce numeric-looking object columns (the classic Telco TotalCharges quirk).
    for c in df.select_dtypes(include="object").columns:
        coerced = pd.to_numeric(df[c], errors="coerce")
        if coerced.notna().mean() > 0.9:
            df[c] = coerced

    target = args.target or df.columns[-1]
    if target not in df.columns:
        raise SystemExit(f"target column '{target}' not in dataframe")

    df = df.dropna(subset=[target]).reset_index(drop=True)
    y = df.pop(target)

    target_type = infer_target_type(y)

    # Encode features: one-hot for objects, leave numerics alone, fill numeric NaNs with median.
    X = pd.get_dummies(df, drop_first=True, dummy_na=False)
    for c in X.select_dtypes(include="number").columns:
        if X[c].isna().any():
            X[c] = X[c].fillna(X[c].median())

    # Encode target.
    if target_type == "regression":
        y_encoded = pd.to_numeric(y, errors="raise")
        class_balance = None
    else:
        codes, uniques = pd.factorize(y, sort=True)
        y_encoded = pd.Series(codes, name=target)
        class_balance = {
            str(label): float((codes == i).mean()) for i, label in enumerate(uniques)
        }

    out_df = pd.concat([X.reset_index(drop=True), y_encoded.rename(target)], axis=1)

    args.output.mkdir(parents=True, exist_ok=True)
    out_df.to_parquet(args.output / "clean.parquet", index=False)

    profile = {
        "rows": len(out_df),
        "cols": len(X.columns),
        "target": target,
        "target_type": target_type,
        "class_balance": class_balance,
    }
    (args.output / "profile.json").write_text(json.dumps(profile, indent=2))

    print(json.dumps(profile, indent=2))


if __name__ == "__main__":
    main()
