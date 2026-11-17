
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC5JJkMTm31FzhnqU-1sRhECUw7wEUA-ik',
  appId: '1:705183829868:web:257762b1344c0ae4842d49',
  messagingSenderId: '705183829868',
  projectId: 'entregue-ja-db433',
  authDomain: 'entregue-ja-db433.firebaseapp.com',
  storageBucket: 'entregue-ja-db433.firebasestorage.app'
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const dados = payload.data || {};

  if (payload.notification) {
    return;
  }

  const titulo = dados.titulo || 'Entregue Já';
  const mensagem = dados.mensagem || 'Você recebeu uma nova notificação.';

  const url = new URL('/', self.location.origin);

  const opcoes = {
    body: mensagem,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: payload.messageId || undefined,
    data: {
      url: url.href,
      tipo: dados.tipo || '',
      tipoConta: dados.tipoConta || '',
      contaId: dados.contaId || '',
      entregaId: dados.entregaId || ''
    }
  };

  return self.registration.showNotification(titulo, opcoes);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const destino = new URL('/', self.location.origin);

  event.waitUntil(
    clients.matchAll({
      type: 'window',
      includeUncontrolled: true
    }).then(async (janelas) => {
      for (const janela of janelas) {
        if (new URL(janela.url).origin === destino.origin) {
          await janela.focus();
          return;
        }
      }

      await clients.openWindow(destino.href);
    })
  );
});
