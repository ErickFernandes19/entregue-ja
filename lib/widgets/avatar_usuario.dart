import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AvatarUsuario extends StatefulWidget {
  final double radius;

  const AvatarUsuario({super.key, this.radius = 24});

  @override
  State<AvatarUsuario> createState() => _AvatarUsuarioState();
}

class _AvatarUsuarioState extends State<AvatarUsuario> {
  String? caminhoFoto;

  @override
  void initState() {
    super.initState();
    carregarFoto();
  }

  Future<void> carregarFoto() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      caminhoFoto = prefs.getString('foto_perfil');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (caminhoFoto == null || caminhoFoto!.isEmpty) {
      return CircleAvatar(
        radius: widget.radius,
        child: const Icon(Icons.person),
      );
    }

    return CircleAvatar(
      radius: widget.radius,
      backgroundImage: FileImage(File(caminhoFoto!)),
    );
  }
}
