package com.example.wechat_flutter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Canal usado pelas notificações push de "Nova mensagem" (importância
        // alta = aparece como aviso na tela, com som).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val canal = NotificationChannel(
                "mensagens",
                "Mensagens",
                NotificationManager.IMPORTANCE_HIGH
            )
            canal.description = "Avisos de novas mensagens"
            val gerenciador = getSystemService(NotificationManager::class.java)
            gerenciador.createNotificationChannel(canal)
        }
    }
}
