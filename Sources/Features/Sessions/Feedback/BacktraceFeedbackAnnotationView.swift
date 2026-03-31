#if os(iOS)
import Foundation
import UIKit
import CoreImage

// MARK: - Annotation Tool Enum

enum AnnotationTool: Int {
    case draw = 0
    case arrow = 1
    case text = 2
    case highlight = 3
    case blur = 4
}

// MARK: - Annotation Action (for undo)

private enum AnnotationAction {
    case path(CAShapeLayer)
    case arrow(CAShapeLayer)
    case textLabel(UILabel)
    case highlight(CAShapeLayer)
    case blur(UIView)
}

// MARK: - Annotation View Controller

/// Full-screen annotation editor for feedback screenshots.
///
/// Provides five tools: freehand draw, arrow, text, highlight, and blur/redact.
/// All drawing is done on a transparent overlay; the final image is composited on save.
final class BacktraceFeedbackAnnotationViewController: UIViewController {

    // MARK: - Properties

    private let originalImage: UIImage
    private var onSave: ((UIImage) -> Void)?

    private let imageView = UIImageView()
    private let canvasView = UIView()
    private var toolbar: UIStackView!

    private var currentTool: AnnotationTool = .draw
    private var currentColor: UIColor = .red
    private var strokeWidth: CGFloat = 3.0

    private var undoStack: [AnnotationAction] = []

    // Drawing state
    private var currentPath: UIBezierPath?
    private var currentShapeLayer: CAShapeLayer?
    private var touchStartPoint: CGPoint = .zero

    // MARK: - Initialization

    init(image: UIImage, onSave: @escaping (UIImage) -> Void) {
        self.originalImage = image
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupNavigationBar()
        setupImageView()
        setupCanvasView()
        setupToolbar()
    }

    // MARK: - Navigation

    private func setupNavigationBar() {
        title = "Annotate"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done", style: .done, target: self, action: #selector(doneTapped)
        )
    }

    // MARK: - UI Setup

    private func setupImageView() {
        imageView.image = originalImage
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
        ])
    }

    private func setupCanvasView() {
        canvasView.backgroundColor = .clear
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.isUserInteractionEnabled = true
        imageView.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: imageView.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
        ])
    }

    private func setupToolbar() {
        let tools: [(String, AnnotationTool)] = [
            ("pencil.tip", .draw),
            ("arrow.right", .arrow),
            ("textformat", .text),
            ("highlighter", .highlight),
            ("eye.slash", .blur),
        ]

        var buttons: [UIView] = []

        for (iconName, tool) in tools {
            let button = UIButton(type: .system)
            button.tag = tool.rawValue
            if #available(iOS 13.0, *) {
                button.setImage(UIImage(systemName: iconName), for: .normal)
            } else {
                button.setTitle(iconName, for: .normal)
            }
            button.tintColor = tool == currentTool ? .systemBlue : .white
            button.addTarget(self, action: #selector(toolSelected(_:)), for: .touchUpInside)
            buttons.append(button)
        }

        // Undo button
        let undoButton = UIButton(type: .system)
        if #available(iOS 13.0, *) {
            undoButton.setImage(UIImage(systemName: "arrow.uturn.backward"), for: .normal)
        } else {
            undoButton.setTitle("Undo", for: .normal)
        }
        undoButton.tintColor = .white
        undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)
        buttons.append(undoButton)

        // Color picker
        let colorButton = UIButton(type: .system)
        colorButton.backgroundColor = currentColor
        colorButton.layer.cornerRadius = 15
        colorButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        colorButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        colorButton.addTarget(self, action: #selector(colorTapped), for: .touchUpInside)
        buttons.append(colorButton)

        toolbar = UIStackView(arrangedSubviews: buttons)
        toolbar.axis = .horizontal
        toolbar.distribution = .equalSpacing
        toolbar.alignment = .center
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    // MARK: - Tool Selection

    @objc private func toolSelected(_ sender: UIButton) {
        guard let tool = AnnotationTool(rawValue: sender.tag) else { return }
        currentTool = tool
        updateToolbarTints()
    }

    @objc private func undoTapped() {
        guard let action = undoStack.popLast() else { return }
        switch action {
        case .path(let layer): layer.removeFromSuperlayer()
        case .arrow(let layer): layer.removeFromSuperlayer()
        case .textLabel(let label): label.removeFromSuperview()
        case .highlight(let layer): layer.removeFromSuperlayer()
        case .blur(let view): view.removeFromSuperview()
        }
    }

    @objc private func colorTapped() {
        let colors: [UIColor] = [.red, .blue, .green, .yellow, .white, .black]
        let currentIndex = colors.firstIndex(of: currentColor) ?? 0
        currentColor = colors[(currentIndex + 1) % colors.count]

        // Update color button
        if let colorButton = toolbar.arrangedSubviews.last as? UIButton {
            colorButton.backgroundColor = currentColor
        }
    }

    private func updateToolbarTints() {
        for view in toolbar.arrangedSubviews {
            guard let button = view as? UIButton else { continue }
            if let tool = AnnotationTool(rawValue: button.tag) {
                button.tintColor = tool == currentTool ? .systemBlue : .white
            }
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: canvasView)
        touchStartPoint = point

        switch currentTool {
        case .draw:
            let path = UIBezierPath()
            path.lineWidth = strokeWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: point)

            let layer = CAShapeLayer()
            layer.strokeColor = currentColor.cgColor
            layer.fillColor = nil
            layer.lineWidth = strokeWidth
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.path = path.cgPath
            canvasView.layer.addSublayer(layer)

            currentPath = path
            currentShapeLayer = layer

        case .arrow, .highlight, .blur:
            // Will handle in touchesMoved/Ended
            break

        case .text:
            addTextAnnotation(at: point)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: canvasView)

        switch currentTool {
        case .draw:
            guard let path = currentPath, let layer = currentShapeLayer else { return }
            path.addLine(to: point)
            layer.path = path.cgPath

        case .arrow:
            currentShapeLayer?.removeFromSuperlayer()
            let layer = createArrowLayer(from: touchStartPoint, to: point)
            canvasView.layer.addSublayer(layer)
            currentShapeLayer = layer

        case .highlight:
            currentShapeLayer?.removeFromSuperlayer()
            let rect = CGRect(
                x: min(touchStartPoint.x, point.x),
                y: min(touchStartPoint.y, point.y),
                width: abs(point.x - touchStartPoint.x),
                height: abs(point.y - touchStartPoint.y)
            )
            let layer = CAShapeLayer()
            layer.path = UIBezierPath(rect: rect).cgPath
            layer.fillColor = UIColor.yellow.withAlphaComponent(0.3).cgColor
            layer.strokeColor = UIColor.yellow.withAlphaComponent(0.6).cgColor
            layer.lineWidth = 1
            canvasView.layer.addSublayer(layer)
            currentShapeLayer = layer

        case .blur:
            // Preview blur rect
            currentShapeLayer?.removeFromSuperlayer()
            let rect = CGRect(
                x: min(touchStartPoint.x, point.x),
                y: min(touchStartPoint.y, point.y),
                width: abs(point.x - touchStartPoint.x),
                height: abs(point.y - touchStartPoint.y)
            )
            let layer = CAShapeLayer()
            layer.path = UIBezierPath(rect: rect).cgPath
            layer.fillColor = UIColor.gray.withAlphaComponent(0.3).cgColor
            layer.strokeColor = UIColor.gray.cgColor
            layer.lineWidth = 1
            layer.lineDashPattern = [4, 4]
            canvasView.layer.addSublayer(layer)
            currentShapeLayer = layer

        case .text:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: canvasView)

        switch currentTool {
        case .draw:
            if let layer = currentShapeLayer {
                undoStack.append(.path(layer))
            }
            currentPath = nil
            currentShapeLayer = nil

        case .arrow:
            currentShapeLayer?.removeFromSuperlayer()
            let layer = createArrowLayer(from: touchStartPoint, to: point)
            canvasView.layer.addSublayer(layer)
            undoStack.append(.arrow(layer))
            currentShapeLayer = nil

        case .highlight:
            if let layer = currentShapeLayer {
                undoStack.append(.highlight(layer))
            }
            currentShapeLayer = nil

        case .blur:
            currentShapeLayer?.removeFromSuperlayer()
            currentShapeLayer = nil
            let rect = CGRect(
                x: min(touchStartPoint.x, point.x),
                y: min(touchStartPoint.y, point.y),
                width: abs(point.x - touchStartPoint.x),
                height: abs(point.y - touchStartPoint.y)
            )
            if rect.width > 10 && rect.height > 10 {
                let blurView = createBlurView(in: rect)
                canvasView.addSubview(blurView)
                undoStack.append(.blur(blurView))
            }

        case .text:
            break
        }
    }

    // MARK: - Arrow Drawing

    private func createArrowLayer(from start: CGPoint, to end: CGPoint) -> CAShapeLayer {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)

        // Arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15
        let arrowAngle: CGFloat = .pi / 6

        let p1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )

        path.move(to: p1)
        path.addLine(to: end)
        path.addLine(to: p2)

        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.strokeColor = currentColor.cgColor
        layer.fillColor = nil
        layer.lineWidth = strokeWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    // MARK: - Text Annotation

    private func addTextAnnotation(at point: CGPoint) {
        let alert = UIAlertController(title: "Add Text", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Enter text..."
        }
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let self = self, let text = alert.textFields?.first?.text, !text.isEmpty else { return }
            let label = UILabel()
            label.text = text
            label.textColor = self.currentColor
            label.font = .boldSystemFont(ofSize: 16)
            label.sizeToFit()
            label.frame.origin = point
            self.canvasView.addSubview(label)
            self.undoStack.append(.textLabel(label))
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Blur/Redact

    private func createBlurView(in rect: CGRect) -> UIView {
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        blurView.frame = rect
        blurView.layer.cornerRadius = 4
        blurView.clipsToBounds = true
        return blurView
    }

    // MARK: - Compositing

    /// Composite the original image with all annotations into a single image.
    private func compositeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: imageView.bounds.size)
        return renderer.image { ctx in
            // Draw original image
            imageView.drawHierarchy(in: imageView.bounds, afterScreenUpdates: true)
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        let result = compositeImage()
        onSave?(result)
        dismiss(animated: true)
    }
}
#endif
