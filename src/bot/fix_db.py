import sqlite3
conn = sqlite3.connect('/data/maubot.db')
cursor = conn.cursor()
cursor.execute("UPDATE client SET access_token = 'syt_bGxtX3dpa2lfYm90_ZkOAdlDPAfydggseIqzd_0334uA' WHERE id = '@llm_wiki_bot:localhost'")
conn.commit()
conn.close()
