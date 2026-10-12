package com.example.wechat_flutter;

import android.app.Activity;
import android.content.Intent;
import android.media.AudioManager;
import android.media.ToneGenerator;
import android.os.Build;
import android.view.WindowManager;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Ponte Dart -> Android: liga/desliga o serviço que mantém a chamada viva. */
public final class CallBridge {
    /** Toque de "chamando" que quem liga ouve até a outra pessoa atender. */
    private static ToneGenerator tom;

    private CallBridge() {
    }

    private static void pararTom() {
        if (tom != null) {
            try {
                tom.stopTone();
                tom.release();
            } catch (RuntimeException ignorado) {
                // sem efeito: só garante que o tom parou
            }
            tom = null;
        }
    }

    public static void registrar(FlutterEngine motor, final Activity atividade) {
        new MethodChannel(motor.getDartExecutor().getBinaryMessenger(), "wechat/chamada")
                .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                    @Override
                    public void onMethodCall(MethodCall chamada, MethodChannel.Result resultado) {
                        if ("iniciar".equals(chamada.method)) {
                            Boolean pedidoVideo = chamada.argument("video");
                            String titulo = chamada.argument("titulo");
                            boolean video = pedidoVideo != null && pedidoVideo;

                            Intent intent = new Intent(atividade, CallForegroundService.class);
                            intent.putExtra("titulo", titulo);
                            intent.putExtra("video", video);
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                atividade.startForegroundService(intent);
                            } else {
                                atividade.startService(intent);
                            }
                            // Chamada de vídeo: não deixa a tela apagar.
                            if (video) {
                                atividade.getWindow().addFlags(
                                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                            }
                            resultado.success(true);
                        } else if ("tocarChamando".equals(chamada.method)) {
                            pararTom();
                            Boolean pedidoVideo = chamada.argument("video");
                            boolean video = pedidoVideo != null && pedidoVideo;
                            // Voz: sai pelo fone de ouvido; vídeo: pelo alto-falante.
                            int fluxo = video
                                    ? AudioManager.STREAM_MUSIC
                                    : AudioManager.STREAM_VOICE_CALL;
                            try {
                                tom = new ToneGenerator(fluxo, 85);
                                tom.startTone(ToneGenerator.TONE_SUP_RINGTONE);
                            } catch (RuntimeException erro) {
                                tom = null;
                            }
                            resultado.success(true);
                        } else if ("pararChamando".equals(chamada.method)) {
                            pararTom();
                            resultado.success(true);
                        } else if ("parar".equals(chamada.method)) {
                            pararTom();
                            atividade.stopService(
                                    new Intent(atividade, CallForegroundService.class));
                            atividade.getWindow().clearFlags(
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                            resultado.success(true);
                        } else {
                            resultado.notImplemented();
                        }
                    }
                });
    }
}
