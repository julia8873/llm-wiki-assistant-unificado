import sqlite3
conn = sqlite3.connect('/data/maubot.db')
cursor = conn.cursor()
cursor.execute("UPDATE client SET next_batch = '', filter_id = '' WHERE id = '@llm_wiki_bot:localhost'")
conn.commit()
conn.close()
