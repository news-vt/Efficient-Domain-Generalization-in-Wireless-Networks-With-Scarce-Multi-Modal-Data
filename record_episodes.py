# python record_episodes.py --episodes 10 --previous_episode 1

import argparse, importlib, carla, sys


def reset_flags(g):
    # g = record_sensor_data
    g.rgb_count = g.lidar_count = g.radar_count = 0


def run_episode(idx: int, host: str, port: int, config_mod, rec_mod):
    # 1) Tag your episode so the save paths inside record_sensor_data.py use /episode_{idx}
    GlobalConfig      = config_mod.GlobalConfig
    record_sensor_data = rec_mod

    GlobalConfig.EPI_NAME = f"/episode_{idx}"

    # 2) Reset and reload the capture module so its lambdas see the new EPI_NAME
    reset_flags(record_sensor_data)
    importlib.reload(record_sensor_data)

    # 3) Hijack sys.argv, then call into record_sensor_data.main()
    old_argv = sys.argv
    sys.argv = [
        "record_sensor_data.py",
        "--host", host,
        "--port", str(port)
    ]
    try:
        record_sensor_data.main()
    finally:
        sys.argv = old_argv


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--episodes", type=int, required=True)
    ap.add_argument("--previous_episode", type=int, default = 0)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", default=2000, type=int)
    args = ap.parse_args()

    pkg_name = "base_station"
    config_mod    = importlib.import_module(f"{pkg_name}.config")
    rec_mod       = importlib.import_module(f"{pkg_name}.record_sensor_data")

    client = carla.Client(args.host, args.port); client.set_timeout(10.)
    for epi in range(args.previous_episode+1, args.episodes):
        print(f"=== CARLA • episode {epi} ===")
        # run_episode(epi, client)          # ❶ just records sensor data
        run_episode(epi, args.host, args.port, config_mod, rec_mod)
    print("✔ all episodes recorded")

if __name__ == "__main__":
    main()