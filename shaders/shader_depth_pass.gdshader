// Seu shader de profundidade (ligeiramente ajustado para clareza)
shader_type spatial;
render_mode unshaded; // Garante que não há cálculos de iluminação

void fragment() {
    // Para um passe de profundidade, o Z-buffer é preenchido automaticamente.
    // Não é necessário escrever em ALBEDO ou ALPHA se o Viewport
    // estiver configurado para apenas capturar a profundidade.
    // Se você quiser ter certeza que objetos transparentes (com alpha < 1)
    // ainda escrevam profundidade de forma opaca (se necessário),
    // você poderia forçar ALPHA = 1.0, mas para shadow mapping de opacos,
    // isso geralmente não é um problema.
}