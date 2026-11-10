#!/usr/bin/env python3
"""
Generates the String Catalogs (13 languages):
  • Shared/Resources/Localizable.xcstrings — UI strings (app + widget extension)
  • App/Resources/InfoPlist.xcstrings      — display name + permission prompts

Source language: English (keys are the English strings, as Xcode extracts them from SwiftUI).
After editing translations here run:  python3 Tools/generate_strings.py
Xcode keeps the catalogs in sync with code on build (new keys appear as "New"), so for new strings you can also
translate directly in Xcode's catalog editor.
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGS = ["fr", "de", "hi", "it", "ja", "ko", "pl", "pt", "ru", "zh-Hans", "es", "tr"]

# key: (fr, de, hi, it, ja, ko, pl, pt, ru, zh-Hans, es, tr)
UI = {
    "%@ is over. Next: %@": ("%1$@ est terminé. Ensuite : %2$@", "%1$@ ist vorbei. Als Nächstes: %2$@", "%1$@ समाप्त। अगला: %2$@", "%1$@ è finito. Prossimo: %2$@", "%1$@ が終了。次は %2$@", "%1$@ 종료. 다음: %2$@", "%1$@ zakończone. Następnie: %2$@", "%1$@ terminou. Próximo: %2$@", "%1$@ — завершено. Далее: %2$@", "%1$@ 已结束。下一个：%2$@", "%1$@ ha terminado. Siguiente: %2$@", "%1$@ bitti. Sıradaki: %2$@"),
    "A one-time purchase that keeps Hourglass independent.": ("Un achat unique qui garde Sablier indépendant.", "Ein einmaliger Kauf, der Sanduhr unabhängig hält.", "एक बार की खरीदारी जो ऐप को स्वतंत्र रखती है।", "Un acquisto unico che mantiene Clessidra indipendente.", "砂時計の開発を支える1回限りの購入です。", "모래시계를 독립적으로 유지하는 1회 구매입니다.", "Jednorazowy zakup, który pozwala Klepsydrze pozostać niezależną.", "Uma compra única que mantém a Ampulheta independente.", "Разовая покупка, которая помогает «Песочным часам» оставаться независимыми.", "一次性购买，支持沙漏独立发展。", "Una compra única que mantiene Reloj de arena independiente.", "Kum Saati'nin bağımsız kalmasını sağlayan tek seferlik satın alma."),
    "Ad privacy choices": ("Choix de confidentialité publicitaire", "Datenschutzoptionen für Werbung", "विज्ञापन गोपनीयता विकल्प", "Scelte sulla privacy degli annunci", "広告のプライバシー設定", "광고 개인정보 보호 선택", "Ustawienia prywatności reklam", "Opções de privacidade de anúncios", "Настройки конфиденциальности рекламы", "广告隐私选项", "Opciones de privacidad de anuncios", "Reklam gizlilik seçenekleri"),
    "Add": ("Ajouter", "Hinzufügen", "जोड़ें", "Aggiungi", "追加", "추가", "Dodaj", "Adicionar", "Добавить", "添加", "Añadir", "Ekle"),
    "Add favourites in the Library.": ("Ajoutez des favoris dans la bibliothèque.", "Füge Favoriten in der Bibliothek hinzu.", "लाइब्रेरी में पसंदीदा जोड़ें।", "Aggiungi preferiti nella Libreria.", "ライブラリでお気に入りを追加してください。", "보관함에서 즐겨찾기를 추가하세요.", "Dodaj ulubione w Bibliotece.", "Adicione favoritos na Biblioteca.", "Добавьте избранное в библиотеке.", "在资料库中添加收藏。", "Añade favoritos en la Biblioteca.", "Kitaplıkta favori ekleyin."),
    "Add final phase": ("Ajouter une phase finale", "Abschlussphase hinzufügen", "अंतिम चरण जोड़ें", "Aggiungi fase finale", "最後のフェーズを追加", "마지막 단계 추가", "Dodaj fazę końcową", "Adicionar fase final", "Добавить финальную фазу", "添加最终阶段", "Añadir fase final", "Son aşama ekle"),
    "Add phase": ("Ajouter une phase", "Phase hinzufügen", "चरण जोड़ें", "Aggiungi fase", "フェーズを追加", "단계 추가", "Dodaj fazę", "Adicionar fase", "Добавить фазу", "添加阶段", "Añadir fase", "Aşama ekle"),
    "After all rounds": ("Après tous les tours", "Nach allen Runden", "सभी राउंड के बाद", "Dopo tutti i round", "全ラウンド終了後", "모든 라운드 후", "Po wszystkich rundach", "Após todas as rodadas", "После всех раундов", "所有轮次之后", "Después de todas las rondas", "Tüm turlardan sonra"),
    "Alarm": ("Alarme", "Wecker", "अलार्म", "Sveglia", "アラーム", "알람", "Alarm", "Alarme", "Сигнал", "闹钟", "Alarma", "Alarm"),
    "Alarms ring even in Silent mode and with Focus on.": ("Les alarmes sonnent même en mode silencieux et avec un Mode de concentration.", "Wecker klingeln auch im Stumm- und Fokusmodus.", "अलार्म साइलेंट मोड और फ़ोकस चालू होने पर भी बजते हैं।", "Le sveglie suonano anche in modalità silenziosa e con la modalità Full immersion.", "アラームは消音モードや集中モードでも鳴ります。", "무음 모드나 집중 모드에서도 알람이 울립니다.", "Alarmy dzwonią nawet w trybie cichym i przy włączonym skupieniu.", "Os alarmes tocam mesmo no modo silencioso e com o Foco ativado.", "Сигналы звучат даже в беззвучном режиме и при включённом фокусе.", "即使在静音模式或专注模式下，闹钟也会响起。", "Las alarmas suenan incluso en modo silencio y con un modo de concentración activado.", "Alarmlar sessiz modda ve Odak açıkken bile çalar."),
    "Alert sound": ("Son d'alerte", "Signalton", "अलर्ट ध्वनि", "Suono di avviso", "通知音", "알림 사운드", "Dźwięk sygnału", "Som de alerta", "Звук сигнала", "提示音", "Sonido de alerta", "Uyarı sesi"),
    "Alerts are delivered as Time Sensitive notifications.": ("Les alertes sont envoyées comme notifications urgentes.", "Hinweise werden als dringende Mitteilungen zugestellt.", "अलर्ट समय-संवेदनशील सूचनाओं के रूप में भेजे जाते हैं।", "Gli avvisi vengono inviati come notifiche urgenti.", "通知は「即時通知」として届きます。", "알림은 시간 민감 알림으로 전달됩니다.", "Powiadomienia są dostarczane jako pilne.", "Os alertas são enviados como notificações urgentes.", "Сигналы приходят как срочные уведомления.", "提醒将作为时效性通知送达。", "Los avisos se envían como notificaciones urgentes.", "Uyarılar Zamana Duyarlı bildirimler olarak iletilir."),
    "Alerts are off — open Settings": ("Alertes désactivées — ouvrir Réglages", "Hinweise sind aus — Einstellungen öffnen", "अलर्ट बंद हैं — सेटिंग्स खोलें", "Avvisi disattivati — apri Impostazioni", "通知がオフです — 設定を開く", "알림이 꺼져 있음 — 설정 열기", "Powiadomienia wyłączone — otwórz Ustawienia", "Alertas desativados — abrir Ajustes", "Уведомления выключены — открыть Настройки", "提醒已关闭 — 打开设置", "Avisos desactivados — abrir Ajustes", "Uyarılar kapalı — Ayarlar'ı aç"),
    "Allow alerts": ("Autoriser les alertes", "Hinweise erlauben", "अलर्ट की अनुमति दें", "Consenti avvisi", "通知を許可", "알림 허용", "Zezwól na powiadomienia", "Permitir alertas", "Разрешить уведомления", "允许提醒", "Permitir avisos", "Uyarılara izin ver"),
    "Allow alerts so the timer can ring when it ends — even when the app is closed, the phone is locked or in Silent mode.": ("Autorisez les alertes pour que le minuteur sonne à la fin — même app fermée, téléphone verrouillé ou en mode silencieux.", "Erlaube Hinweise, damit der Timer am Ende klingelt — auch wenn die App geschlossen, das Telefon gesperrt oder stumm ist.", "अलर्ट की अनुमति दें ताकि टाइमर खत्म होने पर बजे — ऐप बंद हो, फ़ोन लॉक हो या साइलेंट मोड में हो तब भी।", "Consenti gli avvisi così il timer suonerà alla fine — anche con l'app chiusa, il telefono bloccato o in modalità silenziosa.", "通知を許可すると、アプリを閉じていても、ロック中や消音モードでもタイマー終了時に鳴ります。", "알림을 허용하면 앱이 닫혀 있거나 잠금 상태 또는 무음 모드에서도 타이머 종료 시 울립니다.", "Zezwól na powiadomienia, aby minutnik zadzwonił po zakończeniu — nawet gdy aplikacja jest zamknięta, telefon zablokowany lub wyciszony.", "Permita alertas para que o timer toque ao terminar — mesmo com o app fechado, o telefone bloqueado ou no modo silencioso.", "Разрешите уведомления, чтобы таймер прозвенел по окончании — даже если приложение закрыто, телефон заблокирован или в беззвучном режиме.", "允许提醒，计时结束时即可响铃——即使应用已关闭、手机已锁定或处于静音模式。", "Permite los avisos para que el temporizador suene al terminar, incluso con la app cerrada, el teléfono bloqueado o en silencio.", "Uygulama kapalı, telefon kilitli veya sessiz modda olsa bile süre bitince çalması için uyarılara izin verin."),
    "Automatic quality": ("Qualité automatique", "Automatische Qualität", "स्वचालित गुणवत्ता", "Qualità automatica", "画質を自動調整", "자동 품질", "Automatyczna jakość", "Qualidade automática", "Автоматическое качество", "自动画质", "Calidad automática", "Otomatik kalite"),
    "Balanced": ("Équilibré", "Ausgewogen", "संतुलित", "Bilanciata", "バランス", "균형", "Zrównoważona", "Equilibrado", "Сбалансированная", "均衡", "Equilibrada", "Dengeli"),
    "Become a Supporter": ("Devenir Supporter", "Unterstützer werden", "सपोर्टर बनें", "Diventa Sostenitore", "サポーターになる", "서포터 되기", "Zostań Wspierającym", "Torne-se Apoiador", "Стать Supporter", "成为支持者", "Hazte Supporter", "Destekçi ol"),
    "Bell": ("Cloche", "Glocke", "घंटी", "Campana", "ベル", "종", "Dzwon", "Sino", "Колокол", "铃声", "Campana", "Çan"),
    "Cancel": ("Annuler", "Abbrechen", "रद्द करें", "Annulla", "キャンセル", "취소", "Anuluj", "Cancelar", "Отмена", "取消", "Cancelar", "İptal"),
    "Chime": ("Carillon", "Glockenspiel", "झंकार", "Rintocco", "チャイム", "차임", "Kurant", "Carrilhão", "Перезвон", "钟声", "Carillón", "Zil"),
    "Choose between 5 seconds and 24 hours.": ("Choisissez entre 5 secondes et 24 heures.", "Wähle zwischen 5 Sekunden und 24 Stunden.", "5 सेकंड से 24 घंटे के बीच चुनें।", "Scegli tra 5 secondi e 24 ore.", "5秒から24時間の間で選んでください。", "5초에서 24시간 사이로 선택하세요.", "Wybierz od 5 sekund do 24 godzin.", "Escolha entre 5 segundos e 24 horas.", "Выберите от 5 секунд до 24 часов.", "请选择 5 秒到 24 小时之间。", "Elige entre 5 segundos y 24 horas.", "5 saniye ile 24 saat arasında seçin."),
    "Close": ("Fermer", "Schließen", "बंद करें", "Chiudi", "閉じる", "닫기", "Zamknij", "Fechar", "Закрыть", "关闭", "Cerrar", "Kapat"),
    "Delete": ("Supprimer", "Löschen", "हटाएँ", "Elimina", "削除", "삭제", "Usuń", "Apagar", "Удалить", "删除", "Eliminar", "Sil"),
    "Desert": ("Désert", "Wüste", "रेगिस्तान", "Deserto", "砂漠", "사막", "Pustynia", "Deserto", "Пустыня", "沙漠", "Desierto", "Çöl"),
    "Done": ("OK", "Fertig", "हो गया", "Fine", "完了", "완료", "Gotowe", "OK", "Готово", "完成", "OK", "Bitti"),
    "Double-tap to change the duration": ("Touchez deux fois pour modifier la durée", "Doppeltippen, um die Dauer zu ändern", "अवधि बदलने के लिए दो बार टैप करें", "Tocca due volte per cambiare la durata", "ダブルタップで時間を変更", "두 번 탭하여 시간 변경", "Stuknij dwukrotnie, aby zmienić czas", "Toque duas vezes para alterar a duração", "Дважды коснитесь, чтобы изменить длительность", "轻点两下以更改时长", "Toca dos veces para cambiar la duración", "Süreyi değiştirmek için iki kez dokunun"),
    "Duplicate": ("Dupliquer", "Duplizieren", "डुप्लिकेट", "Duplica", "複製", "복제", "Duplikuj", "Duplicar", "Дублировать", "复制", "Duplicar", "Çoğalt"),
    "Duration": ("Durée", "Dauer", "अवधि", "Durata", "時間", "시간", "Czas trwania", "Duração", "Длительность", "时长", "Duración", "Süre"),
    "Edit": ("Modifier", "Bearbeiten", "संपादित करें", "Modifica", "編集", "편집", "Edytuj", "Editar", "Изменить", "编辑", "Editar", "Düzenle"),
    "Edit timer": ("Modifier le minuteur", "Timer bearbeiten", "टाइमर संपादित करें", "Modifica timer", "タイマーを編集", "타이머 편집", "Edytuj minutnik", "Editar timer", "Редактировать таймер", "编辑计时器", "Editar temporizador", "Zamanlayıcıyı düzenle"),
    "Ember": ("Braise", "Glut", "अंगार", "Brace", "残り火", "잉걸불", "Żar", "Brasa", "Угли", "余烬", "Brasa", "Kor"),
    "Favorite": ("Favori", "Favorit", "पसंदीदा", "Preferito", "お気に入り", "즐겨찾기", "Ulubione", "Favorito", "В избранное", "收藏", "Favorito", "Favori"),
    "Flip": ("Retourner", "Umdrehen", "पलटें", "Capovolgi", "反転", "뒤집기", "Odwróć", "Virar", "Перевернуть", "翻转", "Girar", "Çevir"),
    "Flip the device upside down to start, restart or turn the hourglass over. Higher density means more grains and more battery use.": ("Retournez l'appareil pour démarrer, relancer ou retourner le sablier. Une densité plus élevée signifie plus de grains et plus de batterie.", "Drehe das Gerät um, um die Sanduhr zu starten, neu zu starten oder umzudrehen. Höhere Dichte bedeutet mehr Körner und mehr Akkuverbrauch.", "रेत घड़ी शुरू करने, फिर से शुरू करने या पलटने के लिए डिवाइस को उल्टा करें। अधिक घनत्व का अर्थ है अधिक कण और अधिक बैटरी खपत।", "Capovolgi il dispositivo per avviare, riavviare o girare la clessidra. Una densità maggiore significa più granelli e più consumo di batteria.", "デバイスを逆さにすると砂時計を開始・再開・反転できます。密度が高いほど粒が増え、バッテリー消費も増えます。", "기기를 뒤집으면 모래시계를 시작, 재시작하거나 뒤집을 수 있습니다. 밀도가 높을수록 모래알이 많아지고 배터리 사용량이 늘어납니다.", "Odwróć urządzenie, aby uruchomić, zrestartować lub obrócić klepsydrę. Większa gęstość to więcej ziaren i większe zużycie baterii.", "Vire o dispositivo de cabeça para baixo para iniciar, reiniciar ou virar a ampulheta. Mais densidade significa mais grãos e mais uso de bateria.", "Переверните устройство, чтобы запустить, перезапустить или перевернуть часы. Чем выше плотность, тем больше песчинок и расход батареи.", "将设备倒置即可开始、重新开始或翻转沙漏。密度越高，沙粒越多，耗电也越多。", "Pon el dispositivo boca abajo para iniciar, reiniciar o girar el reloj de arena. Más densidad significa más granos y más consumo de batería.", "Kum saatini başlatmak, yeniden başlatmak veya çevirmek için cihazı ters çevirin. Yüksek yoğunluk daha fazla kum tanesi ve pil kullanımı demektir."),
    "Flip to start": ("Retourner pour démarrer", "Zum Starten umdrehen", "शुरू करने के लिए पलटें", "Capovolgi per avviare", "反転して開始", "뒤집어서 시작", "Odwróć, aby uruchomić", "Virar para iniciar", "Переворот для старта", "翻转开始", "Girar para empezar", "Başlatmak için çevir"),
    "Flip your phone or tap Start": ("Retournez votre téléphone ou touchez Démarrer", "Drehe dein Telefon um oder tippe auf Start", "अपना फ़ोन पलटें या शुरू करें पर टैप करें", "Capovolgi il telefono o tocca Avvia", "スマートフォンを反転するか「開始」をタップ", "휴대폰을 뒤집거나 시작을 탭하세요", "Odwróć telefon lub stuknij Start", "Vire o telefone ou toque em Iniciar", "Переверните телефон или нажмите «Старт»", "翻转手机或轻点“开始”", "Gira el teléfono o toca Iniciar", "Telefonu çevirin veya Başlat'a dokunun"),
    "Focus": ("Concentration", "Fokus", "फ़ोकस", "Concentrazione", "集中", "집중", "Skupienie", "Foco", "Фокус", "专注", "Enfoque", "Odak"),
    "Golden Sand": ("Sable doré", "Goldsand", "सुनहरी रेत", "Sabbia dorata", "ゴールデンサンド", "황금 모래", "Złoty piasek", "Areia dourada", "Золотой песок", "金沙", "Arena dorada", "Altın Kum"),
    "Gong": ("Gong", "Gong", "घंटा", "Gong", "ゴング", "징", "Gong", "Gongo", "Гонг", "锣", "Gong", "Gong"),
    "Hourglass": ("Sablier", "Sanduhr", "रेत घड़ी", "Clessidra", "砂時計", "모래시계", "Klepsydra", "Ampulheta", "Песочные часы", "沙漏", "Reloj de arena", "Kum Saati"),
    "Intervals": ("Intervalles", "Intervalle", "अंतराल", "Intervalli", "インターバル", "인터벌", "Interwały", "Intervalos", "Интервалы", "间歇训练", "Intervalos", "Aralıklar"),
    "Intervals 40/20 ×8": ("Intervalles 40/20 ×8", "Intervalle 40/20 ×8", "अंतराल 40/20 ×8", "Intervalli 40/20 ×8", "インターバル 40/20 ×8", "인터벌 40/20 ×8", "Interwały 40/20 ×8", "Intervalos 40/20 ×8", "Интервалы 40/20 ×8", "间歇训练 40/20 ×8", "Intervalos 40/20 ×8", "Aralıklar 40/20 ×8"),
    "Jade": ("Jade", "Jade", "हरिताश्म", "Giada", "翡翠", "비취", "Jadeit", "Jade", "Нефрит", "翡翠", "Jade", "Yeşim"),
    "Keep screen on while running": ("Garder l'écran allumé pendant le minuteur", "Bildschirm während des Timers anlassen", "चलते समय स्क्रीन चालू रखें", "Mantieni lo schermo acceso durante il timer", "実行中は画面をオンのままにする", "실행 중 화면 켜두기", "Nie wygaszaj ekranu podczas odliczania", "Manter a tela ligada durante o timer", "Не гасить экран во время работы", "运行时保持屏幕常亮", "Mantener la pantalla encendida durante el temporizador", "Çalışırken ekranı açık tut"),
    "Lavender": ("Lavande", "Lavendel", "लैवेंडर", "Lavanda", "ラベンダー", "라벤더", "Lawenda", "Lavanda", "Лаванда", "薰衣草", "Lavanda", "Lavanta"),
    "Library": ("Bibliothèque", "Bibliothek", "लाइब्रेरी", "Libreria", "ライブラリ", "보관함", "Biblioteka", "Biblioteca", "Библиотека", "资料库", "Biblioteca", "Kitaplık"),
    "Locked": ("Verrouillé", "Gesperrt", "लॉक है", "Bloccato", "ロック中", "잠김", "Zablokowane", "Bloqueado", "Заблокировано", "已锁定", "Bloqueado", "Kilitli"),
    "Long break": ("Longue pause", "Lange Pause", "लंबा विराम", "Pausa lunga", "長い休憩", "긴 휴식", "Długa przerwa", "Pausa longa", "Длинный перерыв", "长休息", "Descanso largo", "Uzun mola"),
    "Marimba": ("Marimba", "Marimba", "मरिम्बा", "Marimba", "マリンバ", "마림바", "Marimba", "Marimba", "Маримба", "马林巴", "Marimba", "Marimba"),
    "Meditation": ("Méditation", "Meditation", "ध्यान", "Meditazione", "瞑想", "명상", "Medytacja", "Meditação", "Медитация", "冥想", "Meditación", "Meditasyon"),
    "Name": ("Nom", "Name", "नाम", "Nome", "名前", "이름", "Nazwa", "Nome", "Название", "名称", "Nombre", "Ad"),
    "Never miss the last grain": ("Ne manquez jamais le dernier grain", "Verpasse nie das letzte Korn", "आख़िरी कण कभी न चूकें", "Non perderti mai l'ultimo granello", "最後の一粒を見逃さない", "마지막 모래알을 놓치지 마세요", "Nie przegap ostatniego ziarenka", "Nunca perca o último grão", "Не пропустите последнюю песчинку", "不错过最后一粒沙", "No te pierdas el último grano", "Son taneyi asla kaçırmayın"),
    "New sequence": ("Nouvelle séquence", "Neue Sequenz", "नया अनुक्रम", "Nuova sequenza", "新しいシーケンス", "새 시퀀스", "Nowa sekwencja", "Nova sequência", "Новая последовательность", "新序列", "Nueva secuencia", "Yeni dizi"),
    "New timer": ("Nouveau minuteur", "Neuer Timer", "नया टाइमर", "Nuovo timer", "新しいタイマー", "새 타이머", "Nowy minutnik", "Novo timer", "Новый таймер", "新计时器", "Nuevo temporizador", "Yeni zamanlayıcı"),
    "Next phase": ("Phase suivante", "Nächste Phase", "अगला चरण", "Fase successiva", "次のフェーズ", "다음 단계", "Następna faza", "Próxima fase", "Следующая фаза", "下一阶段", "Siguiente fase", "Sonraki aşama"),
    "No account, no server: your timers stay on this device.": ("Ni compte ni serveur : vos minuteurs restent sur cet appareil.", "Kein Konto, kein Server: Deine Timer bleiben auf diesem Gerät.", "कोई खाता नहीं, कोई सर्वर नहीं: आपके टाइमर इसी डिवाइस पर रहते हैं।", "Nessun account, nessun server: i tuoi timer restano su questo dispositivo.", "アカウントもサーバーも不要。タイマーはこのデバイスにのみ保存されます。", "계정도 서버도 없습니다. 타이머는 이 기기에만 저장됩니다.", "Bez konta i serwera: Twoje minutniki zostają na tym urządzeniu.", "Sem conta, sem servidor: seus timers ficam neste dispositivo.", "Без аккаунта и сервера: ваши таймеры хранятся только на этом устройстве.", "无需账户，无需服务器：您的计时器只保存在本设备上。", "Sin cuenta ni servidor: tus temporizadores se quedan en este dispositivo.", "Hesap yok, sunucu yok: zamanlayıcılarınız bu cihazda kalır."),
    "No ads": ("Sans publicité", "Keine Werbung", "कोई विज्ञापन नहीं", "Nessuna pubblicità", "広告なし", "광고 없음", "Bez reklam", "Sem anúncios", "Без рекламы", "无广告", "Sin anuncios", "Reklamsız"),
    "No previous purchases were found for this Apple ID.": ("Aucun achat précédent trouvé pour cet identifiant Apple.", "Für diese Apple-ID wurden keine früheren Käufe gefunden.", "इस Apple ID के लिए कोई पिछली खरीदारी नहीं मिली।", "Nessun acquisto precedente trovato per questo ID Apple.", "このApple IDでの過去の購入は見つかりませんでした。", "이 Apple ID로 이전 구매 내역을 찾을 수 없습니다.", "Nie znaleziono wcześniejszych zakupów dla tego Apple ID.", "Nenhuma compra anterior foi encontrada para este ID Apple.", "Для этого Apple ID покупок не найдено.", "未找到此 Apple ID 的以往购买记录。", "No se encontraron compras anteriores para este ID de Apple.", "Bu Apple Kimliği için önceki satın alma bulunamadı."),
    "No timer running": ("Aucun minuteur en cours", "Kein Timer aktiv", "कोई टाइमर नहीं चल रहा", "Nessun timer attivo", "実行中のタイマーはありません", "실행 중인 타이머 없음", "Brak aktywnego minutnika", "Nenhum timer ativo", "Таймер не запущен", "没有正在运行的计时器", "Ningún temporizador activo", "Çalışan zamanlayıcı yok"),
    "Not now": ("Plus tard", "Nicht jetzt", "अभी नहीं", "Non ora", "今はしない", "나중에", "Nie teraz", "Agora não", "Не сейчас", "以后再说", "Ahora no", "Şimdi değil"),
    "OK": ("OK", "OK", "ठीक है", "OK", "OK", "확인", "OK", "OK", "ОК", "好", "OK", "Tamam"),
    "Ocean": ("Océan", "Ozean", "सागर", "Oceano", "オーシャン", "바다", "Ocean", "Oceano", "Океан", "海洋", "Océano", "Okyanus"),
    "One-time payment. No subscription. Purchases are tied to your Apple ID and restored on all your devices.": ("Paiement unique. Sans abonnement. Les achats sont liés à votre identifiant Apple et restaurés sur tous vos appareils.", "Einmalige Zahlung. Kein Abo. Käufe sind an deine Apple-ID gebunden und auf all deinen Geräten wiederherstellbar.", "एक बार भुगतान। कोई सदस्यता नहीं। खरीदारी आपकी Apple ID से जुड़ी होती है और आपके सभी डिवाइस पर बहाल होती है।", "Pagamento unico. Nessun abbonamento. Gli acquisti sono legati al tuo ID Apple e ripristinati su tutti i tuoi dispositivi.", "1回限りの支払い。サブスクリプションではありません。購入はApple IDに紐づき、すべてのデバイスで復元できます。", "1회 결제. 구독 없음. 구매는 Apple ID에 연결되며 모든 기기에서 복원됩니다.", "Jednorazowa płatność. Bez subskrypcji. Zakupy są powiązane z Apple ID i przywracane na wszystkich urządzeniach.", "Pagamento único. Sem assinatura. As compras ficam vinculadas ao seu ID Apple e são restauradas em todos os seus dispositivos.", "Разовый платёж. Без подписки. Покупка привязана к вашему Apple ID и восстанавливается на всех устройствах.", "一次性付款，非订阅。购买与您的 Apple ID 绑定，可在所有设备上恢复。", "Pago único. Sin suscripción. Las compras se vinculan a tu ID de Apple y se restauran en todos tus dispositivos.", "Tek seferlik ödeme. Abonelik yok. Satın alımlar Apple Kimliğinize bağlıdır ve tüm cihazlarınızda geri yüklenir."),
    "Open the app and flip the hourglass.": ("Ouvrez l'app et retournez le sablier.", "Öffne die App und dreh die Sanduhr um.", "ऐप खोलें और रेत घड़ी पलटें।", "Apri l'app e capovolgi la clessidra.", "アプリを開いて砂時計を反転してください。", "앱을 열고 모래시계를 뒤집으세요.", "Otwórz aplikację i odwróć klepsydrę.", "Abra o app e vire a ampulheta.", "Откройте приложение и переверните часы.", "打开应用并翻转沙漏。", "Abre la app y gira el reloj de arena.", "Uygulamayı açın ve kum saatini çevirin."),
    "Pause": ("Pause", "Pause", "रोकें", "Pausa", "一時停止", "일시정지", "Pauza", "Pausar", "Пауза", "暂停", "Pausa", "Duraklat"),
    "Pause or Resume Timer": ("Mettre en pause ou reprendre le minuteur", "Timer pausieren oder fortsetzen", "टाइमर रोकें या फिर शुरू करें", "Metti in pausa o riprendi il timer", "タイマーを一時停止/再開", "타이머 일시정지 또는 재개", "Wstrzymaj lub wznów minutnik", "Pausar ou retomar o timer", "Пауза или продолжение таймера", "暂停或继续计时器", "Pausar o reanudar el temporizador", "Zamanlayıcıyı duraklat veya sürdür"),
    "Paused": ("En pause", "Pausiert", "रुका हुआ", "In pausa", "一時停止中", "일시정지됨", "Wstrzymano", "Pausado", "На паузе", "已暂停", "En pausa", "Duraklatıldı"),
    "Performance": ("Performance", "Leistung", "प्रदर्शन", "Prestazioni", "パフォーマンス", "성능", "Wydajność", "Desempenho", "Производительность", "性能", "Rendimiento", "Performans"),
    "Phase": ("Phase", "Phase", "चरण", "Fase", "フェーズ", "단계", "Faza", "Fase", "Фаза", "阶段", "Fase", "Aşama"),
    "Phase colour": ("Couleur de la phase", "Phasenfarbe", "चरण का रंग", "Colore della fase", "フェーズの色", "단계 색상", "Kolor fazy", "Cor da fase", "Цвет фазы", "阶段颜色", "Color de la fase", "Aşama rengi"),
    "Phase complete": ("Phase terminée", "Phase beendet", "चरण पूरा", "Fase completata", "フェーズ完了", "단계 완료", "Faza zakończona", "Fase concluída", "Фаза завершена", "阶段完成", "Fase completada", "Aşama tamamlandı"),
    "Phase name": ("Nom de la phase", "Phasenname", "चरण का नाम", "Nome della fase", "フェーズ名", "단계 이름", "Nazwa fazy", "Nome da fase", "Название фазы", "阶段名称", "Nombre de la fase", "Aşama adı"),
    "Phases": ("Phases", "Phasen", "चरण", "Fasi", "フェーズ", "단계", "Fazy", "Fases", "Фазы", "阶段", "Fases", "Aşamalar"),
    "Pomodoro": ("Pomodoro", "Pomodoro", "पोमोडोरो", "Pomodoro", "ポモドーロ", "뽀모도로", "Pomodoro", "Pomodoro", "Помодоро", "番茄钟", "Pomodoro", "Pomodoro"),
    "Pomodoro 25/5 ×4": ("Pomodoro 25/5 ×4", "Pomodoro 25/5 ×4", "पोमोडोरो 25/5 ×4", "Pomodoro 25/5 ×4", "ポモドーロ 25/5 ×4", "뽀모도로 25/5 ×4", "Pomodoro 25/5 ×4", "Pomodoro 25/5 ×4", "Помодоро 25/5 ×4", "番茄钟 25/5 ×4", "Pomodoro 25/5 ×4", "Pomodoro 25/5 ×4"),
    "Premium sand themes: Rose Quartz and Jade": ("Thèmes de sable premium : Quartz rose et Jade", "Premium-Sandthemen: Rosenquarz und Jade", "प्रीमियम रेत थीम: रोज़ क्वार्ट्ज़ और हरिताश्म", "Temi di sabbia premium: Quarzo rosa e Giada", "プレミアムテーマ：ローズクォーツと翡翠", "프리미엄 모래 테마: 로즈 쿼츠와 비취", "Motywy premium: Kwarc różowy i Jadeit", "Temas de areia premium: Quartzo rosa e Jade", "Премиум-темы песка: Розовый кварц и Нефрит", "高级沙子主题：玫瑰石英与翡翠", "Temas de arena premium: Cuarzo rosa y Jade", "Premium kum temaları: Pembe Kuvars ve Yeşim"),
    "Privacy": ("Confidentialité", "Datenschutz", "गोपनीयता", "Privacy", "プライバシー", "개인정보 보호", "Prywatność", "Privacidade", "Конфиденциальность", "隐私", "Privacidad", "Gizlilik"),
    "Purchase": ("Achat", "Kauf", "खरीदारी", "Acquisto", "購入", "구매", "Zakup", "Compra", "Покупка", "购买", "Compra", "Satın alma"),
    "Purchases": ("Achats", "Käufe", "खरीदारियाँ", "Acquisti", "購入", "구매", "Zakupy", "Compras", "Покупки", "购买项目", "Compras", "Satın alımlar"),
    "Purchases are disabled on this device (Screen Time restrictions).": ("Les achats sont désactivés sur cet appareil (restrictions de Temps d'écran).", "Käufe sind auf diesem Gerät deaktiviert (Bildschirmzeit-Beschränkungen).", "इस डिवाइस पर खरीदारी बंद है (स्क्रीन टाइम प्रतिबंध)।", "Gli acquisti sono disattivati su questo dispositivo (restrizioni di Tempo di utilizzo).", "このデバイスでは購入が無効です（スクリーンタイムの制限）。", "이 기기에서 구매가 비활성화되어 있습니다(스크린 타임 제한).", "Zakupy są wyłączone na tym urządzeniu (ograniczenia Czasu przed ekranem).", "As compras estão desativadas neste dispositivo (restrições de Tempo de Uso).", "Покупки отключены на этом устройстве (ограничения «Экранного времени»).", "此设备已停用购买（屏幕使用时间限制）。", "Las compras están desactivadas en este dispositivo (restricciones de Tiempo de uso).", "Bu cihazda satın alma devre dışı (Ekran Süresi kısıtlamaları)."),
    "Quality": ("Qualité", "Qualität", "गुणवत्ता", "Qualità", "高品質", "품질", "Jakość", "Qualidade", "Качество", "画质", "Calidad", "Kalite"),
    "Quick Start": ("Démarrage rapide", "Schnellstart", "त्वरित प्रारंभ", "Avvio rapido", "クイックスタート", "빠른 시작", "Szybki start", "Início rápido", "Быстрый старт", "快速开始", "Inicio rápido", "Hızlı Başlat"),
    "Repeat forever": ("Répéter indéfiniment", "Endlos wiederholen", "हमेशा दोहराएँ", "Ripeti all'infinito", "無限に繰り返す", "무한 반복", "Powtarzaj bez końca", "Repetir para sempre", "Повторять бесконечно", "无限重复", "Repetir siempre", "Sonsuza kadar tekrarla"),
    "Repeats": ("Répétitions", "Wiederholungen", "दोहराव", "Ripetizioni", "繰り返し", "반복", "Powtórzenia", "Repetições", "Повторы", "重复", "Repeticiones", "Tekrarlar"),
    "Reset": ("Réinitialiser", "Zurücksetzen", "रीसेट करें", "Ripristina", "リセット", "재설정", "Resetuj", "Redefinir", "Сбросить", "重置", "Restablecer", "Sıfırla"),
    "Reset all data": ("Réinitialiser toutes les données", "Alle Daten zurücksetzen", "सारा डेटा रीसेट करें", "Ripristina tutti i dati", "すべてのデータをリセット", "모든 데이터 재설정", "Resetuj wszystkie dane", "Redefinir todos os dados", "Сбросить все данные", "重置所有数据", "Restablecer todos los datos", "Tüm verileri sıfırla"),
    "Delete all your data?": ("Réinitialiser toutes les données ?", "Alle Daten zurücksetzen?", "सारा डेटा रीसेट करें?", "Ripristinare tutti i dati?", "すべてのデータをリセットしますか？", "모든 데이터를 재설정할까요?", "Zresetować wszystkie dane?", "Redefinir todos os dados?", "Сбросить все данные?", "要重置所有数据吗？", "¿Restablecer todos los datos?", "Tüm veriler sıfırlansın mı?"),
    "Rest": ("Repos", "Erholung", "आराम", "Riposo", "休息", "휴식", "Odpoczynek", "Descanso", "Отдых", "休息", "Descanso", "Dinlenme"),
    "Restart": ("Relancer", "Neu starten", "फिर से शुरू करें", "Riavvia", "再スタート", "다시 시작", "Uruchom ponownie", "Reiniciar", "Заново", "重新开始", "Reiniciar", "Yeniden başlat"),
    "Restore purchases": ("Restaurer les achats", "Käufe wiederherstellen", "खरीदारी पुनर्स्थापित करें", "Ripristina acquisti", "購入を復元", "구매 복원", "Przywróć zakupy", "Restaurar compras", "Восстановить покупки", "恢复购买", "Restaurar compras", "Satın alımları geri yükle"),
    "Resume": ("Reprendre", "Fortsetzen", "फिर शुरू करें", "Riprendi", "再開", "재개", "Wznów", "Retomar", "Продолжить", "继续", "Reanudar", "Sürdür"),
    "Rose Quartz": ("Quartz rose", "Rosenquarz", "रोज़ क्वार्ट्ज़", "Quarzo rosa", "ローズクォーツ", "로즈 쿼츠", "Kwarc różowy", "Quartzo rosa", "Розовый кварц", "玫瑰石英", "Cuarzo rosa", "Pembe Kuvars"),
    "Rounds: %lld": ("Tours : %lld", "Runden: %lld", "राउंड: %lld", "Round: %lld", "ラウンド：%lld", "라운드: %lld", "Rundy: %lld", "Rodadas: %lld", "Раундов: %lld", "轮次：%lld", "Rondas: %lld", "Tur: %lld"),
    "Sand density": ("Densité du sable", "Sanddichte", "रेत घनत्व", "Densità della sabbia", "砂の密度", "모래 밀도", "Gęstość piasku", "Densidade da areia", "Плотность песка", "沙粒密度", "Densidad de arena", "Kum yoğunluğu"),
    "Sand themes": ("Thèmes de sable", "Sandthemen", "रेत थीम", "Temi di sabbia", "砂のテーマ", "모래 테마", "Motywy piasku", "Temas de areia", "Темы песка", "沙子主题", "Temas de arena", "Kum temaları"),
    "Save": ("Enregistrer", "Sichern", "सहेजें", "Salva", "保存", "저장", "Zapisz", "Salvar", "Сохранить", "保存", "Guardar", "Kaydet"),
    "See how much sand is left.": ("Voyez combien de sable il reste.", "Sieh, wie viel Sand noch übrig ist.", "देखें कितनी रेत बची है।", "Guarda quanta sabbia resta.", "残りの砂を確認できます。", "남은 모래를 확인하세요.", "Zobacz, ile piasku zostało.", "Veja quanta areia resta.", "Сколько песка осталось.", "查看还剩多少沙子。", "Mira cuánta arena queda.", "Ne kadar kum kaldığını görün."),
    "Selected": ("Sélectionné", "Ausgewählt", "चयनित", "Selezionato", "選択中", "선택됨", "Wybrane", "Selecionado", "Выбрано", "已选择", "Seleccionado", "Seçili"),
    "Set": ("Valider", "Festlegen", "सेट करें", "Imposta", "設定", "설정", "Ustaw", "Definir", "Готово", "设定", "Fijar", "Ayarla"),
    "Settings": ("Réglages", "Einstellungen", "सेटिंग्स", "Impostazioni", "設定", "설정", "Ustawienia", "Ajustes", "Настройки", "设置", "Ajustes", "Ayarlar"),
    "Share anonymous usage & crash data": ("Partager des données anonymes d'utilisation et de plantage", "Anonyme Nutzungs- und Absturzdaten teilen", "गुमनाम उपयोग और क्रैश डेटा साझा करें", "Condividi dati anonimi di utilizzo e arresti anomali", "匿名の使用状況とクラッシュデータを共有", "익명 사용 및 충돌 데이터 공유", "Udostępniaj anonimowe dane o użyciu i awariach", "Compartilhar dados anônimos de uso e falhas", "Отправлять анонимные данные об использовании и сбоях", "共享匿名使用和崩溃数据", "Compartir datos anónimos de uso y fallos", "Anonim kullanım ve çökme verilerini paylaş"),
    "Short break": ("Courte pause", "Kurze Pause", "छोटा विराम", "Pausa breve", "短い休憩", "짧은 휴식", "Krótka przerwa", "Pausa curta", "Короткий перерыв", "短休息", "Descanso corto", "Kısa mola"),
    "Skip last phase of the final round": ("Ignorer la dernière phase du dernier tour", "Letzte Phase der letzten Runde überspringen", "अंतिम राउंड का आख़िरी चरण छोड़ें", "Salta l'ultima fase dell'ultimo round", "最終ラウンドの最後のフェーズをスキップ", "마지막 라운드의 마지막 단계 건너뛰기", "Pomiń ostatnią fazę ostatniej rundy", "Pular a última fase da última rodada", "Пропустить последнюю фазу последнего раунда", "跳过最后一轮的最后阶段", "Omitir la última fase de la ronda final", "Son turun son aşamasını atla"),
    "Something went wrong. Please try again later.": ("Un problème est survenu. Réessayez plus tard.", "Etwas ist schiefgelaufen. Bitte versuche es später erneut.", "कुछ गड़बड़ हो गई। कृपया बाद में पुनः प्रयास करें।", "Si è verificato un problema. Riprova più tardi.", "問題が発生しました。しばらくしてからもう一度お試しください。", "문제가 발생했습니다. 나중에 다시 시도하세요.", "Coś poszło nie tak. Spróbuj ponownie później.", "Algo deu errado. Tente novamente mais tarde.", "Что-то пошло не так. Попробуйте позже.", "出了点问题，请稍后重试。", "Algo salió mal. Inténtalo de nuevo más tarde.", "Bir sorun oluştu. Lütfen daha sonra tekrar deneyin."),
    "Start": ("Démarrer", "Start", "शुरू करें", "Avvia", "開始", "시작", "Start", "Iniciar", "Старт", "开始", "Iniciar", "Başlat"),
    "Start Saved Timer": ("Démarrer un minuteur enregistré", "Gespeicherten Timer starten", "सहेजा गया टाइमर शुरू करें", "Avvia timer salvato", "保存したタイマーを開始", "저장된 타이머 시작", "Uruchom zapisany minutnik", "Iniciar timer salvo", "Запустить сохранённый таймер", "开始已存计时器", "Iniciar temporizador guardado", "Kayıtlı zamanlayıcıyı başlat"),
    "Start your favourite timers.": ("Lancez vos minuteurs favoris.", "Starte deine Lieblingstimer.", "अपने पसंदीदा टाइमर शुरू करें।", "Avvia i tuoi timer preferiti.", "お気に入りのタイマーを開始します。", "즐겨 찾는 타이머를 시작하세요.", "Uruchamiaj ulubione minutniki.", "Inicie seus timers favoritos.", "Запускайте избранные таймеры.", "开始您收藏的计时器。", "Inicia tus temporizadores favoritos.", "Favori zamanlayıcılarınızı başlatın."),
    "Stop": ("Arrêter", "Stopp", "रोकें", "Ferma", "停止", "중지", "Zatrzymaj", "Parar", "Стоп", "停止", "Detener", "Durdur"),
    "Stop Timer": ("Arrêter le minuteur", "Timer stoppen", "टाइमर बंद करें", "Ferma timer", "タイマーを停止", "타이머 중지", "Zatrzymaj minutnik", "Parar timer", "Остановить таймер", "停止计时器", "Detener temporizador", "Zamanlayıcıyı durdur"),
    "Store unavailable": ("Store indisponible", "Store nicht verfügbar", "स्टोर उपलब्ध नहीं", "Store non disponibile", "ストアを利用できません", "스토어를 사용할 수 없음", "Sklep niedostępny", "Loja indisponível", "Магазин недоступен", "商店不可用", "Tienda no disponible", "Mağaza kullanılamıyor"),
    "Support future updates": ("Soutenez les futures mises à jour", "Unterstütze künftige Updates", "भविष्य के अपडेट का समर्थन करें", "Sostieni i futuri aggiornamenti", "今後のアップデートを支援", "향후 업데이트 지원", "Wspieraj przyszłe aktualizacje", "Apoie futuras atualizações", "Поддержите будущие обновления", "支持未来更新", "Apoya futuras actualizaciones", "Gelecek güncellemeleri destekleyin"),
    "Supporter": ("Supporter", "Unterstützer", "सपोर्टर", "Sostenitore", "サポーター", "서포터", "Wspierający", "Apoiador", "Supporter", "支持者", "Supporter", "Destekçi"),
    "Supporter — thank you!": ("Supporter — merci !", "Unterstützer — danke!", "सपोर्टर — धन्यवाद!", "Sostenitore — grazie!", "サポーター — ありがとうございます！", "서포터 — 감사합니다!", "Wspierający — dziękujemy!", "Apoiador — obrigado!", "Supporter — спасибо!", "支持者 — 谢谢！", "Supporter — ¡gracias!", "Destekçi — teşekkürler!"),
    "Tap Start to begin": ("Touchez Démarrer pour commencer", "Tippe auf Start, um zu beginnen", "शुरू करने के लिए शुरू करें पर टैप करें", "Tocca Avvia per iniziare", "「開始」をタップしてスタート", "시작을 탭하여 시작하세요", "Stuknij Start, aby rozpocząć", "Toque em Iniciar para começar", "Нажмите «Старт», чтобы начать", "轻点“开始”即可开始", "Toca Iniciar para empezar", "Başlamak için Başlat'a dokunun"),
    "Tea": ("Thé", "Tee", "चाय", "Tè", "お茶", "차", "Herbata", "Chá", "Чай", "泡茶", "Té", "Çay"),
    "Thank you! You are a Supporter.": ("Merci ! Vous êtes Supporter.", "Danke! Du bist Unterstützer.", "धन्यवाद! आप सपोर्टर हैं।", "Grazie! Sei un Sostenitore.", "ありがとうございます！サポーターです。", "감사합니다! 서포터가 되셨습니다.", "Dziękujemy! Jesteś Wspierającym.", "Obrigado! Você é Apoiador.", "Спасибо! Вы — Supporter.", "谢谢！您已成为支持者。", "¡Gracias! Eres Supporter.", "Teşekkürler! Artık Destekçisiniz."),
    "The App Store is not available right now. Please check your connection and try again.": ("L'App Store n'est pas disponible pour le moment. Vérifiez votre connexion et réessayez.", "Der App Store ist gerade nicht verfügbar. Bitte prüfe deine Verbindung und versuche es erneut.", "App Store अभी उपलब्ध नहीं है। कृपया अपना कनेक्शन जाँचें और पुनः प्रयास करें।", "L'App Store non è disponibile al momento. Controlla la connessione e riprova.", "現在App Storeを利用できません。接続を確認してもう一度お試しください。", "지금은 App Store를 사용할 수 없습니다. 연결을 확인한 후 다시 시도하세요.", "App Store jest teraz niedostępny. Sprawdź połączenie i spróbuj ponownie.", "A App Store não está disponível agora. Verifique sua conexão e tente novamente.", "App Store сейчас недоступен. Проверьте подключение и попробуйте ещё раз.", "App Store 当前不可用。请检查网络连接后重试。", "La App Store no está disponible ahora. Comprueba tu conexión e inténtalo de nuevo.", "App Store şu anda kullanılamıyor. Bağlantınızı kontrol edip tekrar deneyin."),
    "The purchase could not be verified.": ("L'achat n'a pas pu être vérifié.", "Der Kauf konnte nicht bestätigt werden.", "खरीदारी सत्यापित नहीं हो सकी।", "Impossibile verificare l'acquisto.", "購入を確認できませんでした。", "구매를 확인할 수 없습니다.", "Nie udało się zweryfikować zakupu.", "Não foi possível verificar a compra.", "Не удалось подтвердить покупку.", "无法验证此购买。", "No se pudo verificar la compra.", "Satın alma doğrulanamadı."),
    "The purchase is pending approval.": ("L'achat est en attente d'approbation.", "Der Kauf wartet auf Genehmigung.", "खरीदारी स्वीकृति की प्रतीक्षा में है।", "L'acquisto è in attesa di approvazione.", "購入は承認待ちです。", "구매가 승인 대기 중입니다.", "Zakup czeka na zatwierdzenie.", "A compra está aguardando aprovação.", "Покупка ожидает подтверждения.", "此购买正在等待批准。", "La compra está pendiente de aprobación.", "Satın alma onay bekliyor."),
    "Themes": ("Thèmes", "Themen", "थीम", "Temi", "テーマ", "테마", "Motywy", "Temas", "Темы", "主题", "Temas", "Temalar"),
    "This purchase is not available in your country or region.": ("Cet achat n'est pas disponible dans votre pays ou région.", "Dieser Kauf ist in deinem Land oder deiner Region nicht verfügbar.", "यह खरीदारी आपके देश या क्षेत्र में उपलब्ध नहीं है।", "Questo acquisto non è disponibile nel tuo paese o area geografica.", "この購入はお住まいの国または地域では利用できません。", "이 구매는 해당 국가 또는 지역에서 사용할 수 없습니다.", "Ten zakup jest niedostępny w Twoim kraju lub regionie.", "Esta compra não está disponível no seu país ou região.", "Эта покупка недоступна в вашей стране или регионе.", "此购买在您所在的国家或地区不可用。", "Esta compra no está disponible en tu país o región.", "Bu satın alma ülkenizde veya bölgenizde kullanılamıyor."),
    "Time remaining": ("Temps restant", "Verbleibende Zeit", "शेष समय", "Tempo rimanente", "残り時間", "남은 시간", "Pozostały czas", "Tempo restante", "Осталось времени", "剩余时间", "Tiempo restante", "Kalan süre"),
    "Time's up!": ("C'est l'heure !", "Zeit ist um!", "समय समाप्त!", "Tempo scaduto!", "時間です！", "시간 종료!", "Czas minął!", "Acabou o tempo!", "Время вышло!", "时间到！", "¡Se acabó el tiempo!", "Süre doldu!"),
    "Timer ID": ("ID du minuteur", "Timer-ID", "टाइमर ID", "ID timer", "タイマーID", "타이머 ID", "ID minutnika", "ID do timer", "ID таймера", "计时器 ID", "ID del temporizador", "Zamanlayıcı kimliği"),
    "Timer theme": ("Thème du minuteur", "Timer-Thema", "टाइमर थीम", "Tema del timer", "タイマーのテーマ", "타이머 테마", "Motyw minutnika", "Tema do timer", "Тема таймера", "计时器主题", "Tema del temporizador", "Zamanlayıcı teması"),
    "Total: %@": ("Total : %@", "Gesamt: %@", "कुल: %@", "Totale: %@", "合計：%@", "합계: %@", "Łącznie: %@", "Total: %@", "Всего: %@", "总计：%@", "Total: %@", "Toplam: %@"),
    "Unlock for %@": ("Débloquer pour %@", "Freischalten für %@", "%@ में अनलॉक करें", "Sblocca per %@", "%@で解除", "%@에 잠금 해제", "Odblokuj za %@", "Desbloquear por %@", "Открыть за %@", "以 %@ 解锁", "Desbloquear por %@", "%@ karşılığında kilidi aç"),
    "Version": ("Version", "Version", "संस्करण", "Versione", "バージョン", "버전", "Wersja", "Versão", "Версия", "版本", "Versión", "Sürüm"),
    "Vibration": ("Vibration", "Vibration", "कंपन", "Vibrazione", "バイブレーション", "진동", "Wibracje", "Vibração", "Вибрация", "振动", "Vibración", "Titreşim"),
    "Volume": ("Volume", "Lautstärke", "वॉल्यूम", "Volume", "音量", "음량", "Głośność", "Volume", "Громкость", "音量", "Volumen", "Ses düzeyi"),
    "Work": ("Effort", "Belastung", "कसरत", "Lavoro", "運動", "운동", "Praca", "Esforço", "Работа", "运动", "Trabajo", "Çalışma"),
    "Your saved timers, sequences and settings will be deleted. Purchases are not affected.": ("Vos minuteurs, séquences et réglages seront supprimés. Les achats ne sont pas affectés.", "Deine gespeicherten Timer, Sequenzen und Einstellungen werden gelöscht. Käufe sind nicht betroffen.", "आपके सहेजे गए टाइमर, अनुक्रम और सेटिंग्स हटा दिए जाएँगे। खरीदारी प्रभावित नहीं होगी।", "I timer salvati, le sequenze e le impostazioni verranno eliminati. Gli acquisti non sono interessati.", "保存したタイマー、シーケンス、設定は削除されます。購入には影響しません。", "저장된 타이머, 시퀀스, 설정이 삭제됩니다. 구매에는 영향이 없습니다.", "Zapisane minutniki, sekwencje i ustawienia zostaną usunięte. Nie dotyczy to zakupów.", "Seus timers, sequências e ajustes salvos serão apagados. As compras não são afetadas.", "Сохранённые таймеры, последовательности и настройки будут удалены. Покупки не затрагиваются.", "您保存的计时器、序列和设置将被删除。购买项目不受影响。", "Se eliminarán tus temporizadores, secuencias y ajustes guardados. Las compras no se ven afectadas.", "Kayıtlı zamanlayıcılarınız, dizileriniz ve ayarlarınız silinecek. Satın alımlar etkilenmez."),
    "Zen mode": ("Mode zen", "Zen-Modus", "ज़ेन मोड", "Modalità Zen", "禅モード", "젠 모드", "Tryb zen", "Modo zen", "Дзен-режим", "禅模式", "Modo zen", "Zen modu"),
    "Zen mode by default": ("Mode zen par défaut", "Standardmäßig Zen-Modus", "डिफ़ॉल्ट रूप से ज़ेन मोड", "Modalità Zen predefinita", "デフォルトで禅モード", "기본적으로 젠 모드", "Domyślnie tryb zen", "Modo zen por padrão", "Дзен-режим по умолчанию", "默认禅模式", "Modo zen por defecto", "Varsayılan olarak Zen modu"),
    "copy": ("copie", "Kopie", "प्रति", "copia", "コピー", "사본", "kopia", "cópia", "копия", "副本", "copia", "kopya"),
    "h": ("h", "Std.", "घं", "h", "時間", "시간", "godz.", "h", "ч", "小时", "h", "sa"),
    "min": ("min", "Min.", "मि", "min", "分", "분", "min", "min", "мин", "分", "min", "dk"),
    "s": ("s", "Sek.", "से", "s", "秒", "초", "s", "s", "с", "秒", "s", "sn"),
}

INFOPLIST = {
    "CFBundleDisplayName": ("Hourglass", UI["Hourglass"]),
    "NSMotionUsageDescription": (
        "Motion data lets the sand fall with real gravity and lets you start the timer by flipping your device.",
        ("Les données de mouvement font tomber le sable selon la gravité réelle et permettent de démarrer le minuteur en retournant l'appareil.",
         "Bewegungsdaten lassen den Sand mit echter Schwerkraft fallen und starten den Timer, wenn du das Gerät umdrehst.",
         "मोशन डेटा से रेत असली गुरुत्व के साथ गिरती है और डिवाइस पलटकर टाइमर शुरू किया जा सकता है।",
         "I dati di movimento fanno cadere la sabbia con la gravità reale e permettono di avviare il timer capovolgendo il dispositivo.",
         "モーションデータにより砂が実際の重力で落ち、デバイスを反転してタイマーを開始できます。",
         "동작 데이터를 사용하면 모래가 실제 중력으로 떨어지고 기기를 뒤집어 타이머를 시작할 수 있습니다.",
         "Dane o ruchu sprawiają, że piasek spada zgodnie z grawitacją, a odwrócenie urządzenia uruchamia minutnik.",
         "Os dados de movimento fazem a areia cair com a gravidade real e permitem iniciar o timer virando o dispositivo.",
         "Данные движения позволяют песку падать по настоящей гравитации и запускать таймер переворотом устройства.",
         "运动数据让沙子随真实重力落下，并可通过翻转设备启动计时器。",
         "Los datos de movimiento hacen que la arena caiga con la gravedad real y permiten iniciar el temporizador girando el dispositivo.",
         "Hareket verileri kumun gerçek yerçekimiyle düşmesini ve cihazı çevirerek zamanlayıcıyı başlatmayı sağlar.")),
    "NSUserTrackingUsageDescription": (
        "Allowing tracking lets us show more relevant ads in the free version. You can say no and the app works the same.",
        ("Autoriser le suivi permet d'afficher des publicités plus pertinentes dans la version gratuite. Vous pouvez refuser, l'app fonctionne de la même façon.",
         "Mit Tracking zeigen wir in der Gratisversion relevantere Werbung. Du kannst ablehnen — die App funktioniert genauso.",
         "ट्रैकिंग की अनुमति देने से मुफ़्त संस्करण में अधिक प्रासंगिक विज्ञापन दिखते हैं। आप मना कर सकते हैं, ऐप वैसे ही काम करेगा।",
         "Consentire il tracciamento ci permette di mostrare annunci più pertinenti nella versione gratuita. Puoi rifiutare e l'app funziona allo stesso modo.",
         "トラッキングを許可すると、無料版でより関連性の高い広告を表示できます。許可しなくてもアプリは同じように動作します。",
         "추적을 허용하면 무료 버전에서 더 관련성 높은 광고를 보여드릴 수 있습니다. 거부해도 앱은 동일하게 작동합니다.",
         "Zgoda na śledzenie pozwala wyświetlać trafniejsze reklamy w wersji darmowej. Możesz odmówić — aplikacja działa tak samo.",
         "Permitir o rastreamento nos deixa mostrar anúncios mais relevantes na versão gratuita. Você pode recusar e o app funciona igual.",
         "Разрешение на отслеживание позволяет показывать более релевантную рекламу в бесплатной версии. Можно отказаться — приложение будет работать так же.",
         "允许跟踪可让我们在免费版中展示更相关的广告。您可以拒绝，应用功能不受影响。",
         "Permitir el seguimiento nos deja mostrar anuncios más relevantes en la versión gratuita. Puedes negarte y la app funciona igual.",
         "İzlemeye izin vermek ücretsiz sürümde daha alakalı reklamlar göstermemizi sağlar. Reddedebilirsiniz; uygulama aynı şekilde çalışır.")),
    "NSAlarmKitUsageDescription": (
        "Alarms make sure your timer rings even in Silent mode or with Focus on.",
        ("Les alarmes garantissent que votre minuteur sonne même en mode silencieux ou avec un Mode de concentration.",
         "Wecker sorgen dafür, dass dein Timer auch im Stumm- oder Fokusmodus klingelt.",
         "अलार्म सुनिश्चित करते हैं कि साइलेंट मोड या फ़ोकस चालू होने पर भी टाइमर बजे।",
         "Le sveglie garantiscono che il timer suoni anche in modalità silenziosa o con la modalità Full immersion attiva.",
         "アラームにより、消音モードや集中モードでもタイマーが鳴ります。",
         "알람을 사용하면 무음 모드나 집중 모드에서도 타이머가 울립니다.",
         "Alarmy sprawiają, że minutnik zadzwoni nawet w trybie cichym lub przy włączonym skupieniu.",
         "Os alarmes garantem que o timer toque mesmo no modo silencioso ou com o Foco ativado.",
         "Будильники гарантируют, что таймер прозвенит даже в беззвучном режиме или при включённом фокусе.",
         "闹钟可确保计时器即使在静音或专注模式下也会响起。",
         "Las alarmas garantizan que el temporizador suene incluso en modo silencio o con un modo de concentración activado.",
         "Alarmlar, zamanlayıcının sessiz modda veya Odak açıkken bile çalmasını sağlar.")),
}

# Keys that must not be translated (identifiers, symbols) are simply not listed; Xcode marks them as stale/new.


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def catalog(entries):
    strings = {}
    for key, (en, tr) in sorted(entries.items()):
        assert len(tr) == len(LANGS), key
        locs = {"en": unit(en)} if en != key else {}
        for lang, val in zip(LANGS, tr):
            locs[lang] = unit(val)
        strings[key] = {"extractionState": "manual", "localizations": locs}
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def write(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    write(ROOT / "Shared/Resources/Localizable.xcstrings", catalog({k: (k, v) for k, v in UI.items()}))
    write(ROOT / "App/Resources/InfoPlist.xcstrings", catalog(INFOPLIST))
    print(f"{len(UI)} UI strings, {len(INFOPLIST)} Info.plist strings × {len(LANGS) + 1} languages")
