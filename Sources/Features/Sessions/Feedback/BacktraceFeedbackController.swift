#if os(iOS)
import Foundation
import UIKit

/// Modal view controller for in-app bug reporting.
///
/// Presents a form with screenshot thumbnail, email field, description field,
/// and optional custom fields. The screenshot is tappable to open the annotation editor.
final class BacktraceFeedbackController: UIViewController {

    // MARK: - Properties

    private let screenshot: UIImage?
    private let options: BacktraceFeedbackOptions
    private let submission: BacktraceFeedbackSubmission
    private weak var sessionDelegate: BacktraceSessionDelegate?

    private var annotatedScreenshot: UIImage?

    // UI elements
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var screenshotImageView: UIImageView?
    private var emailTextField: UITextField?
    private var descriptionTextView: UITextView!
    private var customFieldViews: [String: UIView] = [:]

    // MARK: - Initialization

    init(screenshot: UIImage?,
         options: BacktraceFeedbackOptions,
         submission: BacktraceFeedbackSubmission,
         delegate: BacktraceSessionDelegate?) {
        self.screenshot = screenshot
        self.annotatedScreenshot = screenshot
        self.options = options
        self.submission = submission
        self.sessionDelegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupUI()
    }

    // MARK: - Navigation Bar

    private func setupNavigationBar() {
        title = options.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Submit",
            style: .done,
            target: self,
            action: #selector(submitTapped)
        )
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
        ])

        // Screenshot thumbnail
        if let screenshot = screenshot {
            let imageView = UIImageView(image: screenshot)
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = true
            imageView.heightAnchor.constraint(equalToConstant: 200).isActive = true
            imageView.layer.cornerRadius = 8
            imageView.layer.borderWidth = 1
            imageView.layer.borderColor = UIColor.separator.cgColor
            imageView.clipsToBounds = true

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(screenshotTapped))
            imageView.addGestureRecognizer(tapGesture)

            let label = createLabel("Screenshot (tap to annotate)")
            contentStack.addArrangedSubview(label)
            contentStack.addArrangedSubview(imageView)
            screenshotImageView = imageView
        }

        // Email field
        if options.isEmailVisible {
            let label = createLabel(options.isEmailRequired ? "Email *" : "Email")
            let textField = UITextField()
            textField.placeholder = "your@email.com"
            textField.keyboardType = .emailAddress
            textField.autocapitalizationType = .none
            textField.borderStyle = .roundedRect
            textField.heightAnchor.constraint(equalToConstant: 44).isActive = true
            contentStack.addArrangedSubview(label)
            contentStack.addArrangedSubview(textField)
            emailTextField = textField
        }

        // Description field
        let descLabel = createLabel("Description *")
        descriptionTextView = UITextView()
        descriptionTextView.font = .systemFont(ofSize: 16)
        descriptionTextView.layer.cornerRadius = 8
        descriptionTextView.layer.borderWidth = 1
        descriptionTextView.layer.borderColor = UIColor.separator.cgColor
        descriptionTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        if let defaultText = options.defaultText {
            descriptionTextView.text = defaultText
        }
        contentStack.addArrangedSubview(descLabel)
        contentStack.addArrangedSubview(descriptionTextView)

        // Custom fields
        if let fields = options.customFields {
            for field in fields {
                let label = createLabel(field.required ? "\(field.label) *" : field.label)
                contentStack.addArrangedSubview(label)

                switch field.fieldType {
                case .text, .email:
                    let textField = UITextField()
                    textField.placeholder = field.label
                    textField.borderStyle = .roundedRect
                    textField.keyboardType = field.fieldType == .email ? .emailAddress : .default
                    textField.heightAnchor.constraint(equalToConstant: 44).isActive = true
                    contentStack.addArrangedSubview(textField)
                    customFieldViews[field.key] = textField

                case .textArea:
                    let textView = UITextView()
                    textView.font = .systemFont(ofSize: 16)
                    textView.layer.cornerRadius = 8
                    textView.layer.borderWidth = 1
                    textView.layer.borderColor = UIColor.separator.cgColor
                    textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
                    contentStack.addArrangedSubview(textView)
                    customFieldViews[field.key] = textView

                case .select:
                    // Simple picker using UIButton with menu (iOS 14+)
                    let button = UIButton(type: .system)
                    button.setTitle("Select...", for: .normal)
                    button.contentHorizontalAlignment = .leading
                    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
                    if #available(iOS 14.0, *), let options = field.options {
                        let actions = options.map { option in
                            UIAction(title: option) { [weak button] _ in
                                button?.setTitle(option, for: .normal)
                            }
                        }
                        button.menu = UIMenu(children: actions)
                        button.showsMenuAsPrimaryAction = true
                    }
                    contentStack.addArrangedSubview(button)
                    customFieldViews[field.key] = button
                }
            }
        }
    }

    private func createLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        return label
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func submitTapped() {
        // Validate
        let text = descriptionTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, text.count <= 5000 else {
            showAlert(title: "Invalid Input", message: "Please enter a description (1-5000 characters).")
            return
        }

        if options.isEmailRequired {
            let email = emailTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if email.isEmpty || !email.contains("@") {
                showAlert(title: "Email Required", message: "Please enter a valid email address.")
                return
            }
        }

        // Collect custom field values
        var customValues: [String: String]?
        if let fields = options.customFields {
            var values: [String: String] = [:]
            for field in fields {
                let value: String
                if let textField = customFieldViews[field.key] as? UITextField {
                    value = textField.text ?? ""
                } else if let textView = customFieldViews[field.key] as? UITextView {
                    value = textView.text ?? ""
                } else if let button = customFieldViews[field.key] as? UIButton {
                    value = button.title(for: .normal) ?? ""
                } else {
                    value = ""
                }

                if field.required && value.isEmpty {
                    showAlert(title: "Required Field", message: "\(field.label) is required.")
                    return
                }
                values[field.key] = value
            }
            customValues = values
        }

        // Disable submit button
        navigationItem.rightBarButtonItem?.isEnabled = false

        submission.submit(
            text: text,
            screenshot: annotatedScreenshot,
            email: emailTextField?.text,
            customFields: customValues
        ) { [weak self] (result: Swift.Result<Void, Swift.Error>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.dismiss(animated: true)
                    self.sessionDelegate?.feedbackDidSubmit?()
                case .failure(let error):
                    self.navigationItem.rightBarButtonItem?.isEnabled = true
                    self.showAlert(title: "Submission Failed", message: "Could not send feedback. Please try again.\n\(error.localizedDescription)")
                    self.sessionDelegate?.feedbackDidFailToSubmit?(error: error)
                }
            }
        }
    }

    @objc private func screenshotTapped() {
        guard let screenshot = annotatedScreenshot ?? self.screenshot else { return }
        let annotationVC = BacktraceFeedbackAnnotationViewController(image: screenshot) { [weak self] annotatedImage in
            self?.annotatedScreenshot = annotatedImage
            self?.screenshotImageView?.image = annotatedImage
        }
        let nav = UINavigationController(rootViewController: annotationVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
#endif
