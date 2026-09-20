import { API_URL } from './api';

// Almacenamiento del token en memoria
let currentAccessToken: string | null = null;

export const setApiToken = (token: string | null) => {
  currentAccessToken = token;
};

export const apiClient = async (endpoint: string, options: RequestInit = {}) => {
  // Usar URL absoluta si empieza con http, de lo contrario concatenar con API_URL
  let url = endpoint;
  if (!endpoint.startsWith('http')) {
    // Asegurar que se manejan correctamente las barras inclinadas (slashes) en las rutas
    const path = endpoint.startsWith('/') ? endpoint : `/${endpoint}`;
    url = `${API_URL}${path}`;
  }

  const token = currentAccessToken;

  const config = {
    ...options,
    credentials: 'include' as RequestCredentials,
    headers: {
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...options.headers,
      ...(token ? { 'Authorization': `Bearer ${token}` } : {})
    }
  };

  const response = await fetch(url, config);

  if (response.status === 401 && !url.includes('/v1/token') && !url.includes('/v1/refresh')) {
    window.dispatchEvent(new CustomEvent('auth-unauthorized'));
  }

  return response;
};
