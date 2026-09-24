import logging
import json
import urllib.request
import urllib.error
import asyncio
from urllib.parse import urlparse

logger = logging.getLogger(__name__)

class RestAuthProvider:
    def __init__(self, config, account_handler):
        self.api = account_handler
        self.endpoint = config.get("endpoint")
        self.server_name = self.api.server_name
        
        default_host = urlparse(self.endpoint).netloc if self.endpoint else self.server_name
        self.host_header = config.get("host_header", default_host)

    @staticmethod
    def parse_config(config):
        return config

    async def check_password(self, user_id, password):
        if not self.endpoint:
            return False
            
        logger.info("Moodle auth check started for user_id=%s", user_id)
        
        if user_id.startswith('@'):
            localpart = user_id.split(":", 1)[0][1:]
        else:
            localpart = user_id
            user_id = f"@{localpart}:{self.server_name}"
        
        payload = json.dumps({
            "user": {
                "id": localpart,
                "password": password
            }
        }).encode('utf-8')

        headers = {'Content-Type': 'application/json'}
        if self.host_header:
            headers['Host'] = self.host_header

        req = urllib.request.Request(self.endpoint, data=payload, headers=headers)
        
        def _do_request():
            with urllib.request.urlopen(req, timeout=5) as response:
                return response.status, response.read()
        
        try:
            from twisted.internet import threads
            # Petición HTTP delegada a un hilo para evitar bloquear el event loop de Synapse
            status, body = await threads.deferToThread(_do_request)
            if status == 200:
                res_body = json.loads(body.decode('utf-8'))
                if res_body.get('auth') is True:
                    logger.info("Moodle auth successful for %s", localpart)
                    
                    # Auto-registro en Synapse si no existe
                    try:
                        # Account handler legacy support check
                        if not (await self.api.check_user_exists(user_id)):
                            logger.info("User %s does not exist yet, auto-creating", user_id)
                            await self.api.register_user(localpart=localpart)
                    except Exception as reg_err:
                        logger.error("Failed to auto-register user %s: %s", user_id, str(reg_err))
                        
                    return True
        except urllib.error.HTTPError as e:
            logger.info("Moodle auth failed for %s with HTTP %s", localpart, e.code)
        except Exception as e:
            logger.warning("Error communicating with Moodle auth endpoint: %s", str(e))
            
        return False
