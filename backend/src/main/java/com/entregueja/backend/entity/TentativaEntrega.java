package com.entregueja.backend.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "tentativas_entrega")
public class TentativaEntrega {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "entrega_id", nullable = false)
    private Entrega entrega;

    @Column(nullable = false)
    private Integer numeroTentativa;

    @Column(nullable = false)
    private LocalDateTime dataTentativa;

    @Column(nullable = false)
    private String resultado;

    private String motivo;

    @Column(length = 1000)
    private String justificativa;

    private String fotoComprovante;

    private Double latitude;

    private Double longitude;

    public TentativaEntrega() {
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Entrega getEntrega() {
        return entrega;
    }

    public void setEntrega(Entrega entrega) {
        this.entrega = entrega;
    }

    public Integer getNumeroTentativa() {
        return numeroTentativa;
    }

    public void setNumeroTentativa(Integer numeroTentativa) {
        this.numeroTentativa = numeroTentativa;
    }

    public LocalDateTime getDataTentativa() {
        return dataTentativa;
    }

    public void setDataTentativa(LocalDateTime dataTentativa) {
        this.dataTentativa = dataTentativa;
    }

    public String getResultado() {
        return resultado;
    }

    public void setResultado(String resultado) {
        this.resultado = resultado;
    }

    public String getMotivo() {
        return motivo;
    }

    public void setMotivo(String motivo) {
        this.motivo = motivo;
    }

    public String getJustificativa() {
        return justificativa;
    }

    public void setJustificativa(String justificativa) {
        this.justificativa = justificativa;
    }

    public String getFotoComprovante() {
        return fotoComprovante;
    }

    public void setFotoComprovante(String fotoComprovante) {
        this.fotoComprovante = fotoComprovante;
    }

    public Double getLatitude() {
        return latitude;
    }

    public void setLatitude(Double latitude) {
        this.latitude = latitude;
    }

    public Double getLongitude() {
        return longitude;
    }

    public void setLongitude(Double longitude) {
        this.longitude = longitude;
    }
}