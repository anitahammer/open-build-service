require 'rails_helper'

RSpec.describe Attrib, :type => :model do
  let(:attribute) { create(:attrib, project: create(:project)) }
  let(:project) { create(:project) }
  let(:package) { create(:package) }

  describe "#fullname" do
    it { expect(attribute.fullname).to eq("#{attribute.namespace}:#{attribute.name}") }
  end

  describe "#container" do
    context "attribute with project" do
      it { expect(attribute.container).to eq(attribute.project) }
    end

    context "attribute with package" do
      let(:attribute_with_package) { create(:attrib, package: package) }

      it { expect(attribute_with_package.container).to eq(package) }
    end
  end

  context "#container=" do
    context "assigning a project" do
      before do
        attribute.container = project
      end

      it { expect(attribute.container).to be(project) }
      it { expect(attribute.project).to be(project) }
      it { expect(attribute.package).to be_nil }

      context "and then assigning a package" do
        before do
          attribute.container = package
        end

        it { expect(attribute.container).to be(package) }
        it { expect(attribute.project).to be(package.project) }
        it { expect(attribute.package).to be(package) }
      end
    end

    context "assigning a package" do
      before do
        attribute.container = package
      end

      it { expect(attribute.container).to be(package) }
      it { expect(attribute.project).to be(package.project) }
      it { expect(attribute.package).to be(package) }

      context "and then assigning a project" do
        before do
          attribute.container = project
        end

        it { expect(attribute.container).to be(package) }
        it { expect(attribute.project).to be(package.project) }
        it { expect(attribute.package).to be(package) }
      end
    end
  end

  describe "#project" do
    context "attribute with project" do
      let(:attribute_with_project) { create(:attrib, project: project) }

      it { expect(attribute_with_project.project).to eq(project) }
    end

    context "attribute with package" do
      let(:attribute_with_package) { create(:attrib, package: package) }

      it { expect(attribute_with_package.project).to eq(package.project) }
    end
  end

  describe "#update_with_associations" do
    context "without issues and without values" do
      it { expect(attribute.update_with_associations).to be false }

      context "add an issue" do
        let(:issue_tracker) { create(:issue_tracker) }
        let(:issue) { create(:issue, issue_tracker_id: issue_tracker.id) }
        let(:attrib_type_issue) { create(:attrib_type_with_namespace, issue_list: true) }
        let(:attribute_with_type_issue) { create(:attrib, project: project, attrib_type: attrib_type_issue ) }

        subject { attribute_with_type_issue.update_with_associations([], [issue]) }

        it { expect(subject).to be true }
        it { expect{ subject }.to change{ attribute_with_type_issue.issues.count }.by(1) }
      end

      context "add a value" do
        let(:attrib_value) { build(:attrib_value) }

        subject { attribute.update_with_associations([attrib_value], []) }

        it { expect(subject).to be true }
        it { expect{ subject }.to change{ attribute.values.count }.by(1) }
      end
    end
  end
end
