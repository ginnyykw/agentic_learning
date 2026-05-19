"""Minimal trainer: read config → fit → eval → save → emit one-line JSON."""

import argparse
import json
import pickle
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import f1_score, mean_squared_error, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

SUPPORTED_MODELS = {"xgboost", "logistic_regression"}


def fit_model(model_name: str, params: dict, X_train, y_train, target_type: str):
    if model_name == "xgboost":
        import xgboost as xgb

        params = {"tree_method": "hist", **params}
        cls = xgb.XGBRegressor if target_type == "regression" else xgb.XGBClassifier
        model = cls(**params)
    elif model_name == "logistic_regression":
        params = {"max_iter": 1000, **params}
        model = Pipeline([("scaler", StandardScaler()), ("clf", LogisticRegression(**params))])
    else:
        raise ValueError(f"unsupported model: {model_name} (supported: {sorted(SUPPORTED_MODELS)})")
    model.fit(X_train, y_train)
    return model


def score(metric: str, model, X_test, y_test) -> float:
    if metric == "roc_auc":
        proba = model.predict_proba(X_test)[:, 1]
        return float(roc_auc_score(y_test, proba))
    if metric == "f1_macro":
        return float(f1_score(y_test, model.predict(X_test), average="macro"))
    if metric == "rmse":
        return float(np.sqrt(mean_squared_error(y_test, model.predict(X_test))))
    raise ValueError(f"unsupported metric: {metric}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True, type=Path)
    p.add_argument("--data", required=True, type=Path)
    p.add_argument("--models-dir", required=True, type=Path)
    p.add_argument("--device", default="cpu")  # accepted but ignored in minimal trainer
    args = p.parse_args()

    cfg = json.loads(args.config.read_text())
    profile = json.loads((args.data.parent / "profile.json").read_text())

    df = pd.read_parquet(args.data)
    target = profile["target"]
    X, y = df.drop(columns=[target]), df[target]

    stratify = y if profile["target_type"] != "regression" else None
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=stratify
    )

    t0 = time.time()
    try:
        model = fit_model(cfg["model"], cfg.get("params", {}), X_train, y_train, profile["target_type"])
        metric_value = score(cfg["primary_metric"], model, X_test, y_test)
        status = "ok"
        err = None
    except Exception as e:
        model = None
        metric_value = None
        status = "failed"
        err = f"{type(e).__name__}: {e}"

    duration = time.time() - t0
    artifact_path = None
    if model is not None:
        args.models_dir.mkdir(parents=True, exist_ok=True)
        artifact_path = str(args.models_dir / f"{cfg['run_id']}.pkl")
        with open(artifact_path, "wb") as f:
            pickle.dump(model, f)

    summary = {
        "run_id": cfg["run_id"],
        "model": cfg["model"],
        "primary_metric_name": cfg["primary_metric"],
        "primary_metric_value": metric_value,
        "secondary_metrics_json": json.dumps({"error": err} if err else {}),
        "duration_s": round(duration, 2),
        "status": status,
        "artifact_path": artifact_path or "",
    }
    print(json.dumps(summary))
    sys.exit(0 if status == "ok" else 1)


if __name__ == "__main__":
    main()
