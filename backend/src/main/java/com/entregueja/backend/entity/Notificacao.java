package com.entregueja.backend.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

@Entity
@Table(
        name = "notificacoes",
        indexes = {
                @Index(
                        name = "idx_notificacoes_destinatario",
                        columnList = "tipo_conta, conta_id, criada_em"
                )
        }
)
public class Notificacao {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "tipo_conta", nullable = false, length = 20)
    private String tipoConta;

    @Column(name = "conta_id", nullable = false)
    private Long contaId;

    @Column(nullable = false, length = 60)
    private String tipo;

    @Column(nullable = false, length = 160)
    private String titulo;

    @Column(nullable = false, length = 1000)
    private String mensagem;

    @Column(name = "entrega_id")
    private Long entregaId;

    @Column(nullable = false)
    private boolean lida = false;

    @Column(name = "criada_em", nullable = false, updatable = false)
    private LocalDateTime criadaEm;

    public Notificacao() {
    }

    @PrePersist
    public void antesDeSalvar() {
        if (criadaEm == null) {
            criadaEm = LocalDateTime.now();
        }
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

    public String getTipo() {
        return tipo;
    }

    public void setTipo(String tipo) {
        this.tipo = tipo;
    }

    public String getTitulo() {
        return titulo;
    }

    public void setTitulo(String titulo) {
        this.titulo = titulo;
    }

    public String getMensagem() {
        return mensagem;
    }

    public void setMensagem(String mensagem) {
        this.mensagem = mensagem;
    }

    public Long getEntregaId() {
        return entregaId;
    }

    public void setEntregaId(Long entregaId) {
        this.entregaId = entregaId;
    }

    public boolean isLida() {
        return lida;
    }

    public void setLida(boolean lida) {
        this.lida = lida;
    }

    public LocalDateTime getCriadaEm() {
        return criadaEm;
    }

    public void setCriadaEm(LocalDateTime criadaEm) {
        this.criadaEm = criadaEm;
    }
}
