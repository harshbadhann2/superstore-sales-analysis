"""Forecast monthly Superstore sales with Holt-Winters exponential smoothing.

Run from the project root:  .venv/bin/python notebooks/forecast.py

Steps:
1. Add up sales per month (48 months: Jan 2014 - Dec 2017).
2. Hide the last 6 months, train on the first 42, forecast the hidden 6, measure MAPE.
3. Compare with a simple baseline ("same month last year") so the MAPE has context.
4. Refit on all 48 months and forecast the next 6 (Jan - Jun 2018).
5. Save a chart and the forecast numbers to outputs/.
"""
import matplotlib

matplotlib.use("Agg")  # draw to a file, no window needed
import matplotlib.pyplot as plt
import pandas as pd
from statsmodels.tsa.holtwinters import ExponentialSmoothing

HOLDOUT = 6  # months kept aside to test the model
INK, MUTED, GRID, SURFACE = "#1a1a19", "#6b6a63", "#e6e5df", "#fcfcfb"
ACTUAL, FORECAST = "#2a78d6", "#eb6834"


def mape(actual, forecast):
    """Mean Absolute Percentage Error: on average, how many % the forecast is off by."""
    return (abs(actual - forecast) / actual).mean() * 100


def fit(series):
    # Holt-Winters = exponential smoothing with three parts, each giving more weight to recent months:
    #   level  - the current "normal" monthly sales
    #   trend  - trend="add": sales grow by a roughly steady dollar amount over time
    #   season - seasonal="mul": the yearly pattern (weak Jan/Feb, strong Sep/Nov/Dec) is a % effect,
    #            so the swings get bigger as the business grows. seasonal_periods=12 = one year.
    # Chosen up front (not tuned on the holdout), so the holdout MAPE is an honest test.
    return ExponentialSmoothing(series, trend="add", seasonal="mul", seasonal_periods=12).fit()


df = pd.read_csv("outputs/superstore_clean.csv", parse_dates=["order_date"])
monthly = df.set_index("order_date")["sales"].resample("MS").sum()  # MS = one row per month start

# --- Test on data the model has never seen ---
train, test = monthly[:-HOLDOUT], monthly[-HOLDOUT:]
test_fc = fit(train).forecast(HOLDOUT)
model_mape = mape(test, test_fc)

naive_fc = monthly.shift(12)[-HOLDOUT:]  # baseline: "sales will equal the same month last year"
naive_mape = mape(test, naive_fc)

# --- Final model on all data, forecast the future ---
future = fit(monthly).forecast(HOLDOUT)

print(f"Months of data: {len(monthly)} ({monthly.index[0]:%b %Y} - {monthly.index[-1]:%b %Y})")
print(f"Trained on {len(train)} months, tested on {HOLDOUT} ({test.index[0]:%b %Y} - {test.index[-1]:%b %Y})\n")
print(pd.DataFrame({"actual": test, "forecast": test_fc, "error_%": (test_fc - test) / test * 100}).round(1))
print(f"\nHolt-Winters holdout MAPE:        {model_mape:.1f}%")
print(f"Baseline (same month last year):  {naive_mape:.1f}%\n")
print("Forecast for the next 6 months:")
print(future.round(0).to_string())
print(f"Total: {future.sum():,.0f}")

out = pd.concat([
    pd.DataFrame({"month": test.index, "actual": test.values, "forecast": test_fc.values, "type": "holdout test"}),
    pd.DataFrame({"month": future.index, "actual": float("nan"), "forecast": future.values, "type": "future forecast"}),
])
out.round({"actual": 2, "forecast": 2}).to_csv("outputs/06_sales_forecast.csv", index=False)

# --- Chart ---
fig, ax = plt.subplots(figsize=(11, 5.5), facecolor=SURFACE)
ax.set_facecolor(SURFACE)
ax.axvspan(test.index[0] - pd.Timedelta(days=15), test.index[-1] + pd.Timedelta(days=15), color=GRID, alpha=0.6, lw=0)
ax.text(test.index[0], 0.02, " Holdout (tested)", transform=ax.get_xaxis_transform(), color=MUTED, fontsize=9, va="bottom")

ax.plot(monthly.index, monthly.values, color=ACTUAL, lw=2, label="Actual sales")
ax.plot(test_fc.index, test_fc.values, color=FORECAST, lw=2, ls="--", label=f"Holdout forecast (MAPE {model_mape:.1f}%)")
bridge = pd.concat([monthly[-1:], future])  # connect the last actual month to the forecast
ax.plot(bridge.index, bridge.values, color=FORECAST, lw=2, label="Next 6 months forecast")
ax.plot(future.index, future.values, "o", color=FORECAST, ms=8, mec=SURFACE, mew=2, zorder=3)

ax.annotate(f"${future.sum() / 1000:,.0f}K forecast\nJan-Jun 2018", xy=(future.index[-1], future.iloc[-1]),
            xytext=(8, 0), textcoords="offset points", color=INK, fontsize=9, va="center")
ax.set_title("Superstore monthly sales: actual vs Holt-Winters forecast", loc="left", color=INK, fontsize=13, pad=12)
ax.yaxis.set_major_formatter(lambda v, _: f"${v / 1000:,.0f}K")
ax.grid(axis="y", color=GRID, lw=1)
ax.tick_params(colors=MUTED, length=0)
for side in ("top", "right", "left"):
    ax.spines[side].set_visible(False)
ax.spines["bottom"].set_color(GRID)
ax.set_ylim(bottom=0)
ax.set_xlim(right=future.index[-1] + pd.Timedelta(days=120))
ax.legend(frameon=False, loc="upper left", labelcolor=INK)
fig.tight_layout()
fig.savefig("outputs/forecast.png", dpi=150)
print("\nSaved outputs/forecast.png and outputs/06_sales_forecast.csv")
