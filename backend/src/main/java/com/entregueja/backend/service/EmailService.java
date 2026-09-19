package com.entregueja.backend.service;

import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

@Service
public class EmailService {

    private final JavaMailSender mailSender;

    public EmailService(JavaMailSender mailSender) {
        this.mailSender = mailSender;
    }

    public void enviarCodigoRecuperacao(
            String destinatario,
            String codigo
    ) {
        SimpleMailMessage mensagem = new SimpleMailMessage();

        mensagem.setTo(destinatario);
        mensagem.setSubject("Entregue Já - Recuperação de senha");

        mensagem.setText(
                "Olá!\n\n"
                        + "Recebemos uma solicitação para redefinir sua senha no Entregue Já.\n\n"
                        + "Seu código de recuperação é:\n\n"
                        + codigo
                        + "\n\n"
                        + "Este código é válido por 10 minutos.\n\n"
                        + "Se você não solicitou a recuperação de senha, ignore este e-mail."
        );

        mailSender.send(mensagem);
    }
}