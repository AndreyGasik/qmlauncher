#!/usr/bin/env python3
"""
QM Launcher - Hybrid Python/QML Version (Stable Model)
"""

import sys
import os
import json
import subprocess
import tempfile
import shlex
import ctypes
import math
from pathlib import Path
from PyQt6.QtWidgets import QApplication, QFileDialog, QColorDialog, QInputDialog
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtCore import QObject, pyqtSlot, QUrl, QAbstractListModel, QModelIndex, Qt, QTimer, pyqtSignal
from PyQt6.QtGui import QColor, QFontMetrics, QFont, QRegion, QIcon, QPixmap, QPainter, QPainterPath
from PyQt6 import sip

# ── Иконка приложения ──────────────────────────────────────────────
APP_ID = "qm-launcher"
ICON_BG = "#D08770"     # цвет фона иконки
ICON_FG = "#2E3440"     # цвет букв
ICON_TEXT = "QL"        # буквы на иконке


def make_app_icon() -> QIcon:
    """Собственная иконка окна/приложения — скруглённый квадрат с буквами."""
    size = 128
    pix = QPixmap(size, size)
    pix.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pix)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)

    path = QPainterPath()
    radius = size * 0.22
    path.addRoundedRect(0, 0, size, size, radius, radius)
    painter.setPen(Qt.PenStyle.NoPen)
    painter.setBrush(QColor(ICON_BG))
    painter.drawPath(path)

    painter.setPen(QColor(ICON_FG))
    font = QFont("Sans", int(size * 0.30), QFont.Weight.Bold)
    painter.setFont(font)
    painter.drawText(pix.rect(), Qt.AlignmentFlag.AlignCenter, ICON_TEXT)
    painter.end()
    return QIcon(pix)


class ScriptModel(QAbstractListModel):
    NameRole = Qt.ItemDataRole.UserRole + 1
    PathRole = Qt.ItemDataRole.UserRole + 2
    ItemColorRole = Qt.ItemDataRole.UserRole + 3

    def __init__(self, parent=None):
        super().__init__(parent)
        self._scripts = []
        self.use_terminal = True
        self._save_blocked = False
        self.config_file = Path(__file__).parent / 'launcher_config.json'
        self.load_config()

    def load_config(self):
        if not self.config_file.exists():
            return
        try:
            with open(self.config_file, 'r') as f:
                data = json.load(f)
            if not isinstance(data, dict):
                raise ValueError("config root is not an object")
            scripts = data.get('scripts', [])
            if not isinstance(scripts, list):
                raise ValueError("scripts is not a list")
            self._scripts = scripts
            if 'useTerminal' in data:
                self.use_terminal = bool(data['useTerminal'])
        except Exception as e:
            print(f"Config error: {e}")
            self._scripts = []
            if not self._backup_broken_config():
                # Не затираем оригинал пустым списком, если .bak сделать не удалось.
                self._save_blocked = True
                print("Save disabled: broken config could not be backed up")

    def _backup_broken_config(self):
        bak = self.config_file.with_name(self.config_file.name + '.bak')
        try:
            if bak.exists():
                n = 1
                while True:
                    candidate = self.config_file.with_name(
                        f"{self.config_file.name}.bak.{n}"
                    )
                    if not candidate.exists():
                        bak = candidate
                        break
                    n += 1
            self.config_file.rename(bak)
            print(f"Broken config renamed to {bak.name}")
            return True
        except OSError as e:
            print(f"Could not backup config: {e}")
            return False

    def save_config(self):
        if self._save_blocked:
            print("Save skipped: broken config was not backed up")
            return
        tmp_path = None
        try:
            fd, tmp_path = tempfile.mkstemp(
                dir=str(self.config_file.parent),
                prefix='.launcher_config_',
                suffix='.tmp'
            )
            with os.fdopen(fd, 'w') as f:
                json.dump(
                    {'useTerminal': self.use_terminal, 'scripts': self._scripts},
                    f,
                    indent=2,
                )
            os.replace(tmp_path, self.config_file)
            tmp_path = None
        except Exception as e:
            print(f"Save error: {e}")
        finally:
            if tmp_path is not None:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass

    def set_use_terminal(self, enabled):
        enabled = bool(enabled)
        if enabled == self.use_terminal:
            return
        self.use_terminal = enabled
        self.save_config()

    def rowCount(self, parent=QModelIndex()):
        return len(self._scripts)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or not 0 <= index.row() < len(self._scripts):
            return None
        item = self._scripts[index.row()]
        if role == self.NameRole:
            return item.get('name', Path(item['path']).name)
        elif role == self.PathRole:
            return item['path']
        elif role == self.ItemColorRole:
            return item.get('color', '#ffffff')
        return None

    def roleNames(self):
        return {
            self.NameRole: b'name',
            self.PathRole: b'path',
            self.ItemColorRole: b'itemColor'
        }

    def move_item(self, from_index, to_index):
        if 0 <= from_index < len(self._scripts) and 0 <= to_index < len(self._scripts):
            if to_index > from_index:
                self.beginMoveRows(QModelIndex(), from_index, from_index, QModelIndex(), to_index + 1)
            else:
                self.beginMoveRows(QModelIndex(), from_index, from_index, QModelIndex(), to_index)

            item = self._scripts.pop(from_index)
            self._scripts.insert(to_index, item)
            self.endMoveRows()
            self.save_config()

    def remove_item(self, index):
        if 0 <= index < len(self._scripts):
            self.beginRemoveRows(QModelIndex(), index, index)
            self._scripts.pop(index)
            self.endRemoveRows()
            self.save_config()

    def add_item(self, path):
        if not any(s['path'] == path for s in self._scripts):
            new_item = {
                'path': path,
                'name': Path(path).name,
                'color': '#ffffff'
            }
            self.beginInsertRows(QModelIndex(), len(self._scripts), len(self._scripts))
            self._scripts.append(new_item)
            self.endInsertRows()
            self.save_config()

    def update_name(self, index, name):
        if 0 <= index < len(self._scripts):
            self._scripts[index]['name'] = name
            self.save_config()
            model_index = self.index(index)
            self.dataChanged.emit(model_index, model_index, [self.NameRole])

    def update_color(self, index, color):
        if 0 <= index < len(self._scripts):
            self._scripts[index]['color'] = color
            self.save_config()
            model_index = self.index(index)
            self.dataChanged.emit(model_index, model_index, [self.ItemColorRole])

    def update_path(self, index, new_path):
        if 0 <= index < len(self._scripts):
            self._scripts[index]['path'] = new_path
            self.save_config()
            model_index = self.index(index)
            self.dataChanged.emit(model_index, model_index, [self.PathRole])

class Backend(QObject):
    dialogStateChanged = pyqtSignal(bool)
    scriptError = pyqtSignal(str)

    def __init__(self, engine, window):
        super().__init__()
        self.engine = engine
        self.window = window
        self.model = ScriptModel()

    @pyqtSlot(int, int)
    def moveItem(self, from_index, to_index):
        self.model.move_item(from_index, to_index)

    @pyqtSlot(bool)
    def setUseTerminal(self, enabled):
        self.model.set_use_terminal(enabled)

    @pyqtSlot(result=bool)
    def getUseTerminal(self):
        return self.model.use_terminal

    def _ensure_executable(self, path):
        # chmod только если файл ещё не исполняемый: на чужом разделе
        # chmod падает даже когда +x уже стоит, и тогда запуск не доходит.
        if not os.access(path, os.X_OK):
            os.chmod(path, 0o755)

    def _spawn(self, args, cwd=None):
        env = os.environ.copy()
        # Токен активации уже использован лаунчером — дочернему процессу он мешает.
        env.pop("DESKTOP_STARTUP_ID", None)
        env.pop("XDG_ACTIVATION_TOKEN", None)
        subprocess.Popen(
            list(args),
            cwd=str(cwd) if cwd is not None else None,
            env=env,
            start_new_session=True,
        )

    @pyqtSlot(int)
    def runScript(self, index):
        if not (0 <= index < self.model.rowCount()):
            return

        idx = self.model.index(index)
        path = self.model.data(idx, ScriptModel.PathRole)
        script_path = Path(path)

        if not script_path.exists():
            msg = f"Файл не найден: {script_path}"
            print(msg)
            self.scriptError.emit(msg)
            return

        use_terminal = self.model.use_terminal
        suffix = script_path.suffix.lower()
        cwd = script_path.parent
        try:
            if suffix == '.desktop':
                self._spawn(['xdg-open', str(script_path)], cwd=cwd)
            elif suffix == '.appimage':
                self._ensure_executable(script_path)
                self._spawn([str(script_path)], cwd=cwd)
            elif suffix in ('.sh', '.bash', '.fish'):
                interpreter = "fish" if suffix == ".fish" else "bash"
                if use_terminal:
                    quoted_dir = shlex.quote(str(cwd))
                    quoted_name = shlex.quote(f"./{script_path.name}")
                    cmd = f'cd {quoted_dir}; {interpreter} {quoted_name}; read'
                    self._spawn(['ghostty', '-e', 'fish', '-c', cmd], cwd=cwd)
                else:
                    self._spawn([interpreter, str(script_path)], cwd=cwd)
            elif suffix == '.py':
                self._spawn(['python3', str(script_path)], cwd=cwd)
            elif suffix == '.exe':
                self._spawn(['wine', str(script_path)], cwd=cwd)
            elif suffix == '':
                # Без расширения chmod 755 к любому файлу не применяем:
                # исполняемый — запускаем, иначе открываем через xdg-open.
                if os.access(script_path, os.X_OK):
                    self._spawn([str(script_path)], cwd=cwd)
                else:
                    self._spawn(['xdg-open', str(script_path)], cwd=cwd)
            else:
                self._spawn(['xdg-open', str(script_path)], cwd=cwd)

            QTimer.singleShot(100, self.window.close)

        except FileNotFoundError as e:
            msg = f"Программа не найдена: {e.filename or e}"
            print(msg)
            self.scriptError.emit(msg)
        except Exception as e:
            msg = f"Ошибка запуска: {e}"
            print(msg)
            self.scriptError.emit(msg)

    @pyqtSlot()
    def addFile(self):
        self.dialogStateChanged.emit(True)
        try:
            file_path, _ = QFileDialog.getOpenFileName(
                None, "Выберите файл", str(Path.home()), "Все файлы (*)"
            )
            if file_path:
                self.model.add_item(file_path)
        finally:
            self.dialogStateChanged.emit(False)

    @pyqtSlot(int)
    def renameItem(self, index):
        if not (0 <= index < self.model.rowCount()):
            return
        idx = self.model.index(index)
        current_name = self.model.data(idx, ScriptModel.NameRole)

        self.dialogStateChanged.emit(True)
        try:
            new_name, ok = QInputDialog.getText(
                None, "Переименовать", "Новое имя:", text=current_name
            )
            if ok and new_name.strip():
                self.model.update_name(index, new_name.strip())
        finally:
            self.dialogStateChanged.emit(False)

    @pyqtSlot(int)
    def editPath(self, index):
        if not (0 <= index < self.model.rowCount()):
            return
        idx = self.model.index(index)
        current_path = self.model.data(idx, ScriptModel.PathRole)

        self.dialogStateChanged.emit(True)
        try:
            new_path, ok = QInputDialog.getText(
                None, "Изменить путь", "Путь к файлу:",
                text=current_path
            )
            if ok and new_path.strip():
                self.model.update_path(index, new_path.strip())
        finally:
            self.dialogStateChanged.emit(False)

    @pyqtSlot(int)
    def chooseColor(self, index):
        if not (0 <= index < self.model.rowCount()):
            return
        idx = self.model.index(index)
        current_color = self.model.data(idx, ScriptModel.ItemColorRole)

        self.dialogStateChanged.emit(True)
        try:
            try:
                result = subprocess.run(
                    ['kcolorchooser', '--color', current_color, '--print'],
                    capture_output=True,
                    text=True
                )
            except FileNotFoundError:
                # Qt-диалог — только если kcolorchooser не установлен.
                color = QColorDialog.getColor(
                    QColor(current_color), None, "Выберите цвет текста"
                )
                if color.isValid():
                    self.model.update_color(index, color.name())
                return

            # Отмена и любой ненулевой код — не открываем второй диалог.
            if result.returncode == 0:
                color_hex = result.stdout.strip()
                if color_hex.startswith('#') and len(color_hex) == 7:
                    self.model.update_color(index, color_hex)
        finally:
            self.dialogStateChanged.emit(False)

    @pyqtSlot(int)
    def removeItem(self, index):
        if 0 <= index < self.model.rowCount():
            self.model.remove_item(index)

    @pyqtSlot(result=int)
    def getMaxNameWidth(self):
        font = QFont()
        font.setPointSize(12)
        fm = QFontMetrics(font)
        max_width = 0
        # 8+8 (рамка) + 12+12 (колонка) + 16+16 (строка) + 24 (бейдж) + 12 (зазор)
        padding = 108
        for i in range(self.model.rowCount()):
            idx = self.model.index(i)
            name = self.model.data(idx, ScriptModel.NameRole)
            if name:
                width = fm.horizontalAdvance(str(name)) + padding
                if width > max_width:
                    max_width = width
        return max(max_width, 300)

class KWinBlur:
    """Просит KWin (Better Blur DX) размыть фон за окном.
    Вызывает KWindowEffects::enableBlurBehind из libKF6WindowSystem через ctypes."""
    SYMBOL = "_ZN14KWindowEffects16enableBlurBehindEP7QWindowbRK7QRegion"

    def __init__(self, window, margin=8, radius=16):
        self.window = window
        self.margin = margin    # должен совпадать с anchors.margins основного Rectangle в QML
        self.radius = radius    # должен совпадать с radius основного Rectangle в QML
        self._fn = None
        try:
            lib = ctypes.CDLL("libKF6WindowSystem.so.6")
            fn = getattr(lib, self.SYMBOL)
            fn.argtypes = [ctypes.c_void_p, ctypes.c_bool, ctypes.c_void_p]
            fn.restype = None
            self._fn = fn
        except (OSError, AttributeError) as e:
            print(f"Blur недоступен: {e}")
            return
        # ширина окна меняется (updateWidth в QML) — обновляем область размытия
        window.widthChanged.connect(self.apply)
        window.heightChanged.connect(self.apply)
        window.visibleChanged.connect(self.apply)

    def _build_region(self):
        """Скруглённый прямоугольник построчно (1px-полосы): точнее, чем полигон.
        Вписан на 1px внутрь, чтобы размытие не вылезало за сглаженный край фона."""
        inset = 1
        x0 = self.margin + inset
        y0 = self.margin + inset
        w = self.window.width() - 2 * x0
        h = self.window.height() - 2 * y0
        r = max(0, self.radius - inset)
        if w <= 0 or h <= 0:
            return QRegion()
        r = min(r, w // 2, h // 2)
        region = QRegion(x0, y0 + r, w, h - 2 * r)          # центральная часть
        for i in range(r):                                   # скруглённые верх и низ
            d = r - i - 0.5
            dx = int(math.ceil(r - math.sqrt(max(0.0, r * r - d * d))))
            region += QRegion(x0 + dx, y0 + i, w - 2 * dx, 1)
            region += QRegion(x0 + dx, y0 + h - 1 - i, w - 2 * dx, 1)
        return region

    def apply(self, *_):
        if not self._fn or not self.window.isVisible():
            return
        region = self._build_region()
        self._fn(sip.unwrapinstance(self.window), True, sip.unwrapinstance(region))

def main():
    # Уникальный argv[0] (X11 WM_CLASS) и desktopFileName (Wayland app-id),
    # иначе DE группирует все python-скрипты в одну кнопку с общей иконкой.
    sys.argv[0] = APP_ID
    app = QApplication(sys.argv)
    app.setApplicationName("QM Launcher")
    app.setDesktopFileName(APP_ID)
    app.setWindowIcon(make_app_icon())
    app.setStyle('Fusion')

    engine = QQmlApplicationEngine()

    qml_file = Path(__file__).parent / 'launcher.qml'

    # Регистрируем контекст ДО загрузки QML — иначе QML не видит модель при инициализации
    # Создаём временный backend без root_window, передадим его после загрузки
    backend = Backend(engine, None)
    engine.rootContext().setContextProperty("scriptModel", backend.model)
    engine.rootContext().setContextProperty("pythonBackend", backend)

    engine.load(QUrl.fromLocalFile(str(qml_file)))

    if not engine.rootObjects():
        print("Error loading QML")
        return -1

    root_window = engine.rootObjects()[0]
    backend.window = root_window
    root_window.setIcon(make_app_icon())

    # Блюр фона через KWin; держим ссылку, чтобы объект не собрал GC
    blur = KWinBlur(root_window)
    QTimer.singleShot(0, blur.apply)
    QTimer.singleShot(200, blur.apply)

    backend.dialogStateChanged.connect(lambda state: root_window.setProperty("isDialogOpen", state))
    backend.scriptError.connect(lambda msg: root_window.setProperty("errorMessage", msg))

    return app.exec()

if __name__ == '__main__':
    sys.exit(main())
