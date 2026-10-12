package com.example.wechat_flutter;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

/**
 * Serviço em primeiro plano que mantém microfone (e câmera, em vídeo)
 * funcionando quando o app vai para segundo plano ou a tela apaga.
 */
public class CallForegroundService extends Service {
    private static final String CANAL = "chamada_em_andamento";
    private static final int ID_NOTIFICACAO = 7001;

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String titulo = "Chamada em andamento";
        boolean video = false;
        if (intent != null) {
            String t = intent.getStringExtra("titulo");
            if (t != null) {
                titulo = t;
            }
            video = intent.getBooleanExtra("video", false);
        }

        criarCanal();

        PendingIntent toque = null;
        Intent abrir = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (abrir != null) {
            abrir.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            int marcas = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                marcas |= PendingIntent.FLAG_IMMUTABLE;
            }
            toque = PendingIntent.getActivity(this, 0, abrir, marcas);
        }

        Notification.Builder construtor;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            construtor = new Notification.Builder(this, CANAL);
        } else {
            construtor = new Notification.Builder(this);
        }
        construtor.setContentTitle(titulo);
        construtor.setContentText("Toque para voltar à chamada");
        construtor.setSmallIcon(getApplicationInfo().icon);
        construtor.setOngoing(true);
        construtor.setCategory(Notification.CATEGORY_CALL);
        if (toque != null) {
            construtor.setContentIntent(toque);
        }
        Notification notificacao = construtor.build();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            int tipos = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE;
            if (video) {
                tipos |= ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA;
            }
            startForeground(ID_NOTIFICACAO, notificacao, tipos);
        } else {
            startForeground(ID_NOTIFICACAO, notificacao);
        }
        return START_NOT_STICKY;
    }

    private void criarCanal() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel canal = new NotificationChannel(
                    CANAL,
                    "Chamada em andamento",
                    NotificationManager.IMPORTANCE_LOW);
            canal.setDescription("Mantém a chamada ativa em segundo plano");
            NotificationManager gerenciador = getSystemService(NotificationManager.class);
            if (gerenciador != null) {
                gerenciador.createNotificationChannel(canal);
            }
        }
    }
}
