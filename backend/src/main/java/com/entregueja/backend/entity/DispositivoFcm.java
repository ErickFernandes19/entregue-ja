package com.entregueja.backend.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.time.LocalDateTime;

@Entity
@Table(
        name = "dispositivos_fcm",
        uniqueConstraints = @UniqueConstraint(
                name = "uk_dispositivo_fcm_token",
                columnNames = "token"
        ),
        indexes = @Index(
                name = "idx_dispositivo_fcm_conta",
                columnList = "tipo_conta, conta_id"
        )
)
public class DispositivoFcm {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "tipo_conta", nullable = false, length = 20)
    private String tipoConta;

    @Column(name = "conta_id", nullable = false)
    private Long contaId;

    @Column(name = "token", nullable = false, length = 2048)
    private String token;

    @Column(name = "plataforma", nullable = false, length = 20)
    private String plataforma = "ANDROID";

    @Column(name = "criado_em", nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @Column(name = "atualizado_em", nullable = false)
    private LocalDateTime atualizadoEm;

    public DispositivoFcm() {
    }

    public DispositivoFcm(String tipoConta, Long contaId, String token, String plataforma) {
        this.tipoConta = tipoConta;
        this.contaId = contaId;
        this.token = token;
        this.plataforma = plataforma;
    }

    @PrePersist
    public void antesDeCriar() {
        LocalDateTime agora = LocalDateTime.now();
        criadoEm = agora;
        atualizadoEm = agora;
    }

    @PreUpdate
    public void antesDeAtualizar() {
        atualizadoEm = LocalDateTime.now();
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getTipoConta() {
        return tipoConta;
    }

    public void setTipoConta(String tipoConta) {
        this.tipoConta = tipoConta;
    }

    public Long getContaId() {
        return contaId;
    }

    public void setContaId(Long contaId) {
        this.contaId = contaId;
    }

    public String getToken() {
        return token;
    }

    public void setToken(String token) {
        this.token = token;
    }

    public String getPlataforma() {
        return plataforma;
    }

    public void setPlataforma(String plataforma) {
        this.plataforma = plataforma;
    }

    public LocalDateTime getCriadoEm() {
        return criadoEm;
    }

    public void setCriadoEm(LocalDateTime criadoEm) {
        this.criadoEm = criadoEm;
    }

    public LocalDateTime getAtualizadoEm() {
        return atualizadoEm;
    }

    public void setAtualizadoEm(LocalDateTime atualizadoEm) {
        this.atualizadoEm = atualizadoEm;
    }
}
