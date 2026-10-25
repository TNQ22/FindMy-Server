// FindMy Server Offline Service Worker
const CACHE_NAME = 'findmy-server-cache-v1';

const STATIC_ASSETS = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
  'assets/FontManifest.json',
  'assets/AssetManifest.json',
  'assets/OpenHaystackIcon.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS).catch((err) => {
        console.warn('[SW] Pre-caching partial failure:', err);
      });
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);

  // Skip caching for backend API requests & Google OAuth endpoints
  if (
    url.pathname.startsWith('/api/') ||
    url.hostname.includes('accounts.google.com') ||
    url.hostname.includes('googleapis.com') ||
    request.method !== 'GET'
  ) {
    return;
  }

  // Network-First with Cache Fallback for static assets & application shell
  event.respondWith(
    fetch(request)
      .then((networkResponse) => {
        // Cache successful response for offline usage
        if (networkResponse && networkResponse.status === 200) {
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(request, responseToCache).catch(() => {});
          });
        }
        return networkResponse;
      })
      .catch(async () => {
        // Network failed (offline or server unreachable), retrieve from cache
        const cachedResponse = await caches.match(request);
        if (cachedResponse) {
          return cachedResponse;
        }

        // If navigation request (HTML page), fallback to root index.html
        if (request.mode === 'navigate') {
          const indexCached = await caches.match('index.html') || await caches.match('./');
          if (indexCached) {
            return indexCached;
          }
        }

        return new Response('Ngoại tuyến: Không có kết nối mạng', {
          status: 503,
          statusText: 'Service Unavailable',
          headers: new Headers({ 'Content-Type': 'text/plain; charset=utf-8' })
        });
      })
  );
});
