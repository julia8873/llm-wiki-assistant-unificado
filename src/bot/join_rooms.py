import requests
token = "syt_bGxtX3dpa2lfYm90_ZkOAdlDPAfydggseIqzd_0334uA"
url = "http://synapse:8008/_matrix/client/v3/sync?timeout=0"
headers = {"Authorization": f"Bearer {token}"}
resp = requests.get(url, headers=headers)
data = resp.json()
invites = data.get("rooms", {}).get("invite", {})
for room_id in invites.keys():
    print(f"Joining {room_id}...")
    join_url = f"http://synapse:8008/_matrix/client/v3/join/{room_id}"
    res = requests.post(join_url, headers=headers)
    print(res.status_code, res.text)
