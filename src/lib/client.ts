type ApiResponse<T = unknown> = { data: T; status: number };

type ApiError = Error & {
  response?: { status: number; data: { error?: string; message?: string } };
  code?: string;
};

async function request<T = unknown>(method: string, url: string, body?: unknown): Promise<ApiResponse<T>> {
  const response = await fetch(url, {
    method,
    credentials: 'include',
    headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const contentType = response.headers.get('content-type') || '';
  const data = contentType.includes('application/json') ? await response.json() : await response.text();
  if (!response.ok) {
    const err = new Error((data && typeof data === 'object' && ('error' in data || 'message' in data))
      ? String((data as { error?: string; message?: string }).error || (data as { error?: string; message?: string }).message)
      : `HTTP ${response.status}`) as ApiError;
    err.response = { status: response.status, data: typeof data === 'object' && data ? data as { error?: string; message?: string } : { error: String(data) } };
    throw err;
  }
  return { data: data as T, status: response.status };
}

export const api = {
  get: <T = unknown>(url: string) => request<T>('GET', url),
  post: <T = unknown>(url: string, body?: unknown) => request<T>('POST', url, body),
  put: <T = unknown>(url: string, body?: unknown) => request<T>('PUT', url, body),
  delete: <T = unknown>(url: string) => request<T>('DELETE', url),
};

export const auth = {
  async getUser() {
    try {
      const response = await request<{ user: unknown }>('GET', '/api/auth/me');
      return response.data.user;
    } catch (err) {
      const status = (err as ApiError).response?.status;
      if (status === 401) return null;
      throw err;
    }
  },
  async signIn(credentials: { email: string; password: string }) {
    const response = await request<{ user: unknown }>('POST', '/api/auth/login', credentials);
    return response.data;
  },
  async signOut() {
    await request('POST', '/api/auth/logout', {});
  },
};
